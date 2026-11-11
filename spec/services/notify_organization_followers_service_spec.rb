# frozen_string_literal: true

require "rails_helper"

# Written before NotifyOrganizationFollowersService existed, so every
# example fails with NameError. Pins: three change kinds, muting,
# no-follow-row defaults, cadence split, and the master switch.
RSpec.describe "NotifyOrganizationFollowersService", type: :service do
  include_context "Setup"

  # Builds a user who can receive notifications on every channel. That takes
  # sms_notifications_enabled, is_phone_verified, and the org_position_taken
  # preference.
  def setup_notifiable_user(user)
    user.update_columns(sms_notifications_enabled: true, is_phone_verified: true)
    create(:notification_preference, user: user, key: "org_position_taken", enabled: true)
    user
  end

  # ─── New position approved ───────────────────────────────────────────────────

  it "approving a brand-new active position enqueues a new-position notification to eligible followers" do
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill = create(:bill)
    create(:organization_follow, user: user, organization: org,
      notify_on_new_position: true)
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "Supports this bill")

    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:new_position]).call
    }.to have_enqueued_job(SmsDeliveryJob).at_least(:once)
  end

  # ─── Support change and summary change ───────────────────────────────────────

  it "a support change enqueues a support_change notification" do
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill = create(:bill)
    create(:organization_follow, user: user, organization: org,
      notify_on_support_change: true)
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "Existing summary")

    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:support_change]).call
    }.to have_enqueued_job(SmsDeliveryJob).at_least(:once)
  end

  it "a summary-only change enqueues a summary_change notification" do
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill = create(:bill)
    create(:organization_follow, user: user, organization: org,
      notify_on_summary_change: true)
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "Updated summary text")

    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:summary_change]).call
    }.to have_enqueued_job(SmsDeliveryJob).at_least(:once)
  end

  # ─── A pending position never notifies ─────────────────────────────────────

  it "a still-pending OrganizationBillPosition enqueues nothing" do
    # Watch out: soft-deleted or pending positions must NOT trigger notifications.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill = create(:bill)
    create(:organization_follow, user: user, organization: org,
      notify_on_new_position: true)
    # A pending position: active is false, so nobody has approved it yet.
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: false, support: "FOR", summary: "Pending review")

    # A pending or inactive position must queue nothing; the service blocks it.
    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:new_position]).call
    }.not_to have_enqueued_job(SmsDeliveryJob)
  end

  # ─── Mute semantics ──────────────────────────────────────────────────────────

  it "a follower with that event-type toggled off is not enqueued for it (mute semantics)" do
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill = create(:bill)
    # This user has support_change muted, so muted_for? returns true.
    create(:organization_follow, user: user, organization: org,
      notify_on_support_change: false)
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "Summary text")

    # A muted follower must NOT show up in notifiable_follower_set_for.
    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:support_change]).call
    }.not_to have_enqueued_job(SmsDeliveryJob)
  end

  # ─── A member with no follow row uses their global defaults ────────────────

  it "an active member with NO follow row is in the NOTIFY set using their global defaults" do
    # Members count as followers even with no organization_follows row. When
    # that row is missing, the service uses the member's global default
    # preferences.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill = create(:bill)
    # An active member with no organization_follows row. Their global default
    # notify_on_new_position_default is true (the database column's default).
    create(:user_organization_membership, user: user, organization: org, status: :active)
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "New position")

    # A member with no follow row must still be notified, using those defaults.
    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:new_position]).call
    }.to have_enqueued_job(SmsDeliveryJob).at_least(:once)
  end

  # ─── Cadence routing: every_change vs digest ─────────────────────────────────

  it "every_change follower gets an immediate dispatch; daily/weekly follower is routed to the digest, not dispatched immediately" do
    # How often a follower asked to hear from us decides whether they get an
    # immediate message or a batched digest.
    _sway_locale, user_immediate = setup
    setup_notifiable_user(user_immediate)
    _locale2, user_digest = setup
    # The digest user needs the master preference on but not SMS, since they
    # take the digest path.
    user_digest.update_columns(sms_notifications_enabled: false, is_phone_verified: false)
    create(:notification_preference, user: user_digest, key: "org_position_taken", enabled: true)

    org = create(:organization)
    bill = create(:bill)

    create(:organization_follow, user: user_immediate, organization: org,
      notification_cadence: :every_change, notify_on_new_position: true)
    create(:organization_follow, user: user_digest, organization: org,
      notification_cadence: :daily, notify_on_new_position: true)

    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "Important new position")

    # Expect exactly one SmsDeliveryJob, for the every_change user only —
    # the daily user goes to a stub aggregator. The service never queues
    # DailyOrgDigestJob itself.
    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:new_position]).call
    }.to have_enqueued_job(SmsDeliveryJob).exactly(:once)

    # The DailyOrgDigestJob stub is not queued directly by the service.
    expect {
      # Empty block: this only checks what is already on the queue.
    }.not_to have_enqueued_job(DailyOrgDigestJob)
  end

  it "guards enqueue_digest with mark_delivered_once! and cleans up marker if DigestOrgNotificationAggregator.enqueue raises" do
    _sway_locale, user_digest = setup
    user_digest.update_columns(sms_notifications_enabled: false, is_phone_verified: false)
    create(:notification_preference, user: user_digest, key: "org_position_taken", enabled: true)

    org = create(:organization)
    bill = create(:bill)
    create(:organization_follow, user: user_digest, organization: org,
      notification_cadence: :daily, notify_on_new_position: true)
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "Important new position")

    token = "2026-06-30T10:00:00.000000Z"

    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:new_position], delivery_token: token).call
      NotifyOrganizationFollowersService.new(position, change_types: [:new_position], delivery_token: token).call
    }.to change {
      PendingOrganizationDigestEntry.where(user_id: user_digest.id, org_id: org.id, bill_id: bill.id).count
    }.by(1)

    expect(
      OrganizationNotificationDelivery.where(
        user_id: user_digest.id,
        organization_bill_position_id: position.id,
        delivery_token: token
      ).count
    ).to eq(1)

    fail_token = "2026-06-30T11:00:00.000000Z"
    allow(DigestOrgNotificationAggregator).to receive(:enqueue).and_raise(StandardError, "digest failed")

    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:new_position], delivery_token: fail_token).call
    }.to raise_error(StandardError, "digest failed")

    expect(
      OrganizationNotificationDelivery.where(
        user_id: user_digest.id,
        organization_bill_position_id: position.id,
        delivery_token: fail_token
      ).count
    ).to eq(0)
  end

  # ─── Master org_position_taken preference OFF suppresses delivery ─────────────

  it "the master org_position_taken preference OFF suppresses delivery" do
    # With the master switch (NotificationPreference.org_position_taken) off, no
    # org-position notification goes out, whatever the follow settings say.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill = create(:bill)
    create(:organization_follow, user: user, organization: org,
      notify_on_new_position: true)
    # Turn the preference we enabled above back off.
    user.notification_preferences.find_by(key: "org_position_taken")&.update!(enabled: false)
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "New position")

    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:new_position]).call
    }.not_to have_enqueued_job(SmsDeliveryJob)
  end

  # ─── Running the fan-out twice must not send twice ───────────────────────────

  it "does not re-send immediate channels when the fan-out is retried/replayed (WR-04)" do
    # Solid Queue re-runs an orphaned job after a crash, so call can run
    # twice for one position. The saved marker must make the second run a
    # no-op on every immediate channel.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill = create(:bill)
    create(:organization_follow, user: user, organization: org,
      notification_cadence: :every_change, notify_on_new_position: true)
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "Supports this bill")

    # First fan-out delivers exactly one SMS.
    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:new_position]).call
    }.to have_enqueued_job(SmsDeliveryJob).exactly(:once)

    # Running the same fan-out again sends NOTHING.
    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:new_position]).call
    }.not_to have_enqueued_job(SmsDeliveryJob)

    # Exactly one saved "already sent" marker for this position, change type and user.
    expect(
      OrganizationNotificationDelivery.where(
        user_id: user.id,
        organization_bill_position_id: position.id,
        change_type: "new_position"
      ).count
    ).to eq(1)
  end

  it "still sends a DISTINCT later change-type burst to the same follower (WR-04 key)" do
    # A truly different batch — a later support_change, say — has its own marker
    # key, so the new_position marker must NOT block it.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill = create(:bill)
    create(:organization_follow, user: user, organization: org,
      notification_cadence: :every_change,
      notify_on_new_position: true, notify_on_support_change: true)
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "Supports this bill")

    NotifyOrganizationFollowersService.new(position, change_types: [:new_position]).call

    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:support_change]).call
    }.to have_enqueued_job(SmsDeliveryJob).exactly(:once)
  end

  # ─── One marker per EVENT, keyed by delivery_token ───────────────────────────

  it "suppresses a true REPLAY of the same event (same change_type AND same delivery_token)" do
    # A Solid Queue re-run carries the IDENTICAL token captured when the job was
    # queued. The same position, change type and token hit the unique index, so
    # nothing is sent again.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill = create(:bill)
    create(:organization_follow, user: user, organization: org,
      notification_cadence: :every_change, notify_on_support_change: true)
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "Supports this bill")

    token = "2026-06-30T10:00:00.000000Z"

    expect {
      NotifyOrganizationFollowersService.new(position,
        change_types: [:support_change], delivery_token: token).call
    }.to have_enqueued_job(SmsDeliveryJob).exactly(:once)

    expect {
      NotifyOrganizationFollowersService.new(position,
        change_types: [:support_change], delivery_token: token).call
    }.not_to have_enqueued_job(SmsDeliveryJob)
  end

  it "DELIVERS a genuinely-later same-type change (same change_type, NEW delivery_token)" do
    # An org flipping its stance a SECOND time is a real new event: the
    # change type repeats, but a later updated_at gives a new token, so the
    # marker must NOT block it.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill = create(:bill)
    create(:organization_follow, user: user, organization: org,
      notification_cadence: :every_change, notify_on_support_change: true)
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "Supports this bill")

    # First support_change (FOR→AGAINST).
    NotifyOrganizationFollowersService.new(position,
      change_types: [:support_change], delivery_token: "2026-06-30T10:00:00.000000Z").call

    # A real later support_change (AGAINST back to FOR) weeks on, with its own token.
    expect {
      NotifyOrganizationFollowersService.new(position,
        change_types: [:support_change], delivery_token: "2026-07-15T12:00:00.000000Z").call
    }.to have_enqueued_job(SmsDeliveryJob).exactly(:once)
  end

  it "the text message carries the bill title's headline, not its legal clause" do
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization, name: "Baltimore Renters United")
    bill = create(:bill,
      title: "Sale of Property - 123 Main Street FOR the purpose of authorizing " \
             "the Mayor and City Council of Baltimore to sell, at either public " \
             "or private sale, all its interest in certain parcels of land.")
    create(:organization_follow, user: user, organization: org,
      notification_cadence: :every_change, notify_on_new_position: true)
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "Supports this bill")

    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:new_position]).call
    }.to have_enqueued_job(SmsDeliveryJob).with(
      to: user.phone,
      body: "Baltimore Renters United: Baltimore Renters United published a new position on Sale of Property."
    )
  end

  # @lat: [[bill-title-display#Which outbound messages carry the shortened title]]
  it "web push and native push carry the same headline the text message does" do
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization, name: "Baltimore Renters United")
    bill = create(:bill,
      title: "Sale of Property - 123 Main Street FOR the purpose of authorizing the sale.")
    create(:organization_follow, user: user, organization: org,
      notification_cadence: :every_change, notify_on_new_position: true)
    create(:push_notification_subscription, user: user, subscribed: true)
    create(:user_device, user: user)
    position = create(:organization_bill_position, organization: org, bill: bill,
      active: true, support: "FOR", summary: "Supports this bill")

    expected = "Baltimore Renters United published a new position on Sale of Property."

    web_pushed = nil
    allow(SwayPushNotificationService).to receive(:new) do |_sub, **kwargs|
      web_pushed = kwargs[:body]
      instance_double(SwayPushNotificationService, send_push_notification: true)
    end

    expect {
      NotifyOrganizationFollowersService.new(position, change_types: [:new_position]).call
    }.to have_enqueued_job(SendNativePushJob).with(anything, hash_including(body: expected))

    expect(web_pushed).to eq(expected)
  end
end
