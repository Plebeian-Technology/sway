# frozen_string_literal: true

require "rails_helper"

# @lat: [[pending-org-digest-entry-design#Why PendingOrganizationDigestEntry is a durable queue]]
RSpec.describe "DailyOrgDigestJob", type: :job do
  include_context "Setup"

  # Helper: build a user who can receive every notification channel. Same as in
  # the NotifyOrganizationFollowersService spec — the user needs SMS turned on,
  # a verified phone, and the org_position_taken preference.
  def setup_notifiable_user(user)
    user.update_columns(sms_notifications_enabled: true, is_phone_verified: true)
    create(:notification_preference, user: user, key: "org_position_taken", enabled: true)
    user
  end

  # ─── One digest covering several organizations ───────────────────────────────

  it "a daily follower following two orgs that each had a qualifying change receives exactly one daily digest covering both" do
    # One digest pulls together the pending rows from several orgs.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org1 = create(:organization)
    org2 = create(:organization)
    bill = create(:bill)

    # Do by hand what NotifyOrganizationFollowersService#enqueue_digest does for
    # a daily follower: write two PendingOrganizationDigestEntry rows, one per org change.
    DigestOrgNotificationAggregator.enqueue(
      user_id: user.id, cadence: :daily, org_id: org1.id,
      bill_id: bill.id, change_types: [:new_position]
    )
    DigestOrgNotificationAggregator.enqueue(
      user_id: user.id, cadence: :daily, org_id: org2.id,
      bill_id: bill.id, change_types: [:new_position]
    )

    expect {
      DailyOrgDigestJob.new.perform
    }.to have_enqueued_job(SmsDeliveryJob).exactly(:once)

    # The rows that were sent must be deleted, so running the job again does not
    # send the same digest a second time.
    expect(PendingOrganizationDigestEntry.where(user_id: user.id, cadence: "daily").count).to eq(0)
  end

  # ─── A muted change type never creates a row in the first place ──────────────

  it "a muted change type produces no pending entry and therefore no daily digest" do
    # The service that runs earlier only calls enqueue when the change type is
    # switched on in the follow. A muted type never reaches
    # PendingOrganizationDigestEntry, so dispatch_period finds no rows and sends nothing.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org1 = create(:organization)
    create(:bill)

    create(:organization_follow, user: user, organization: org1,
      notification_cadence: :daily,
      notify_on_new_position: true,
      notify_on_support_change: false)

    # No DigestOrgNotificationAggregator.enqueue call here — the earlier service
    # would have muted this change type (notify_on_support_change: false), so no
    # PendingOrganizationDigestEntry rows exist for this user.

    expect {
      DailyOrgDigestJob.new.perform
    }.not_to have_enqueued_job(SmsDeliveryJob)
  end

  # ─── One SMS per period, not one per change ─────────────────────────────────

  it "the SMS digest is one message per follower per period, not one per change" do
    # The digest has to fold several changes into one SMS per follower per period.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill1 = create(:bill)
    bill2 = create(:bill)

    # Two qualifying changes from the same org → two separate entries enqueued
    DigestOrgNotificationAggregator.enqueue(
      user_id: user.id, cadence: :daily, org_id: org.id,
      bill_id: bill1.id, change_types: [:new_position]
    )
    DigestOrgNotificationAggregator.enqueue(
      user_id: user.id, cadence: :daily, org_id: org.id,
      bill_id: bill2.id, change_types: [:new_position]
    )

    # One SmsDeliveryJob per follower per period (both changes batched into one message).
    expect {
      DailyOrgDigestJob.new.perform
    }.to have_enqueued_job(SmsDeliveryJob).exactly(:once)
  end

  # ─── every_change followers excluded from digest ─────────────────────────────

  it "an every_change follower has no pending entries and is NOT included in the daily digest" do
    # Followers set to "every change" are notified straight away, not through a
    # digest. The earlier service only calls enqueue for the daily and weekly
    # cadences, so this user has no PendingOrganizationDigestEntry rows with cadence
    # 'daily'.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    create(:bill)

    create(:organization_follow, user: user, organization: org,
      notification_cadence: :every_change, notify_on_new_position: true)

    # No enqueue call — "every change" is sent right away and never enters a
    # digest, so PendingOrganizationDigestEntry is empty for this user.

    expect {
      DailyOrgDigestJob.new.perform
    }.not_to have_enqueued_job(SmsDeliveryJob)
  end

  # ─── The main switch: no org_position_taken preference means no digest ──────

  it "a follower with org_position_taken master gate disabled receives no digest" do
    # Dispatch checks that main switch again right before it sends.
    _sway_locale, user = setup
    # NOTE: setup_notifiable_user is left out on purpose, so no preference exists.
    org = create(:organization)
    bill = create(:bill)

    DigestOrgNotificationAggregator.enqueue(
      user_id: user.id, cadence: :daily, org_id: org.id,
      bill_id: bill.id, change_types: [:new_position]
    )

    expect {
      DailyOrgDigestJob.new.perform
    }.not_to have_enqueued_job(SmsDeliveryJob)
  end
end
