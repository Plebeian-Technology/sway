# frozen_string_literal: true

require "rails_helper"

# @lat: [[pending-org-digest-entry-design#Why PendingOrganizationDigestEntry is a durable queue]]
RSpec.describe "WeeklyOrgDigestJob", type: :job do
  include ActiveSupport::Testing::TimeHelpers

  include_context "Setup"

  # Helper: build a user who can receive every kind of notification.
  def setup_notifiable_user(user)
    user.update_columns(sms_notifications_enabled: true, is_phone_verified: true)
    create(:notification_preference, user: user, key: "org_position_taken", enabled: true)
    user
  end

  # ─── One digest covering several orgs over seven days ────────────────────────

  it "a weekly follower following two orgs that each had a qualifying change within 7 days receives exactly one weekly digest covering both" do
    # One weekly digest rolls up seven days of changes from more than one org.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org1 = create(:organization)
    org2 = create(:organization)
    bill = create(:bill)

    DigestOrgNotificationAggregator.enqueue(
      user_id: user.id, cadence: :weekly, org_id: org1.id,
      bill_id: bill.id, change_types: [:new_position]
    )
    DigestOrgNotificationAggregator.enqueue(
      user_id: user.id, cadence: :weekly, org_id: org2.id,
      bill_id: bill.id, change_types: [:new_position]
    )

    # Exactly one weekly digest for this user across both orgs.
    expect {
      WeeklyOrgDigestJob.new.perform
    }.to have_enqueued_job(SmsDeliveryJob).exactly(:once)

    # Entries must be deleted once they have been sent.
    expect(PendingOrganizationDigestEntry.where(user_id: user.id, cadence: "weekly").count).to eq(0)
  end

  # ─── A change type muted for an org creates no entry ────────────────────────

  it "a muted change type produces no pending entry and therefore no weekly digest" do
    # With every change type muted, nothing upstream calls enqueue, so the
    # weekly dispatch finds no rows and sends nothing.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org1 = create(:organization)

    create(:organization_follow, user: user, organization: org1,
      notification_cadence: :weekly,
      notify_on_new_position: false,
      notify_on_support_change: false,
      notify_on_summary_change: false)

    # Nothing is enqueued, because every type is muted upstream.

    expect {
      WeeklyOrgDigestJob.new.perform
    }.not_to have_enqueued_job(SmsDeliveryJob)
  end

  # ─── One text message per period, not one per change ─────────────────────────

  it "the weekly SMS digest is one message per follower per period, not one per change" do
    # Several qualifying changes inside the seven days become a single text.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill1 = create(:bill, scheduled_release_date_utc: 1.day.ago)
    bill2 = create(:bill, scheduled_release_date_utc: 2.days.ago)
    bill3 = create(:bill, scheduled_release_date_utc: 3.days.ago)

    DigestOrgNotificationAggregator.enqueue(
      user_id: user.id, cadence: :weekly, org_id: org.id,
      bill_id: bill1.id, change_types: [:new_position]
    )
    DigestOrgNotificationAggregator.enqueue(
      user_id: user.id, cadence: :weekly, org_id: org.id,
      bill_id: bill2.id, change_types: [:support_change]
    )
    DigestOrgNotificationAggregator.enqueue(
      user_id: user.id, cadence: :weekly, org_id: org.id,
      bill_id: bill3.id, change_types: [:summary_change]
    )

    # One SmsDeliveryJob per follower per period; all three changes ride along in
    # that single message.
    expect {
      WeeklyOrgDigestJob.new.perform
    }.to have_enqueued_job(SmsDeliveryJob).exactly(:once)
  end

  # ─── Followers on every_change or daily stay out of the weekly digest ────────

  it "every_change and daily cadence followers are NOT included in the weekly digest" do
    # The job handles only entries marked 'weekly'. There are no weekly
    # PendingOrganizationDigestEntry rows here, so it sends nothing.
    _sway_locale, user_every = setup
    _locale2, user_daily = setup

    setup_notifiable_user(user_every)
    setup_notifiable_user(user_daily)

    org = create(:organization)
    create(:bill)

    # These cadences go elsewhere: every_change sends right away, daily goes to
    # DailyOrgDigestJob. Neither ever creates a weekly entry.
    create(:organization_follow, user: user_every, organization: org,
      notification_cadence: :every_change, notify_on_new_position: true)
    create(:organization_follow, user: user_daily, organization: org,
      notification_cadence: :daily, notify_on_new_position: true)

    # No weekly PendingOrganizationDigestEntry rows exist.

    expect {
      WeeklyOrgDigestJob.new.perform
    }.not_to have_enqueued_job(SmsDeliveryJob)
  end

  # ─── Surviving a missed or late run, and never sending twice ─────────────────

  it "still dispatches a durably-recorded entry created BEFORE the nominal window (durability)" do
    # @lat: [[pending-org-digest-entry-design#Why dispatch_period selects with no created_at window]]
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill = create(:bill)

    travel_to(8.days.ago) do
      DigestOrgNotificationAggregator.enqueue(
        user_id: user.id, cadence: :weekly, org_id: org.id,
        bill_id: bill.id, change_types: [:new_position]
      )
    end

    # The old entry still goes out, and is then deleted.
    expect {
      WeeklyOrgDigestJob.new.perform
    }.to have_enqueued_job(SmsDeliveryJob).exactly(:once)

    expect(PendingOrganizationDigestEntry.where(user_id: user.id, cadence: "weekly").count).to eq(0)
  end

  it "is idempotent — a second run after dispatch sends no duplicate digest" do
    # Deleting rows after sending, not any time window, is what prevents a
    # second send.
    _sway_locale, user = setup
    setup_notifiable_user(user)
    org = create(:organization)
    bill = create(:bill)

    DigestOrgNotificationAggregator.enqueue(
      user_id: user.id, cadence: :weekly, org_id: org.id,
      bill_id: bill.id, change_types: [:new_position]
    )

    expect {
      WeeklyOrgDigestJob.new.perform
    }.to have_enqueued_job(SmsDeliveryJob).exactly(:once)

    # The rows are gone, so running the job again sends nothing.
    expect {
      WeeklyOrgDigestJob.new.perform
    }.not_to have_enqueued_job(SmsDeliveryJob)
  end

  it "purges orphaned rows whose user no longer resolves — no leak, no delivery (WR-01/CR-03)" do
    _sway_locale, _user = setup
    org = create(:organization)
    bill = create(:bill)

    # Add a row pointing at a user_id that does not exist. The table has no
    # foreign key, and insert! skips the belongs_to validation, so this stands in
    # for a row whose user was deleted outright, back before deleting a user
    # cleaned these up. The dispatch must delete such a row, not strand it.
    PendingOrganizationDigestEntry.insert!({
      user_id: 999_999, cadence: "weekly", org_id: org.id, bill_id: bill.id,
      change_types: "new_position", created_at: Time.current, updated_at: Time.current
    })

    expect {
      WeeklyOrgDigestJob.new.perform
    }.not_to have_enqueued_job(SmsDeliveryJob)

    expect(PendingOrganizationDigestEntry.where(cadence: "weekly").count).to eq(0)
  end
end
