# frozen_string_literal: true

require "rails_helper"

# @lat: [[pending-org-digest-entry-design#Why PendingOrganizationDigestEntry is a durable queue]]
# @lat: [[pending-org-digest-entry-design#Why dispatch_period uses keyset pagination by recipient]]
# @lat: [[pending-org-digest-entry-design#Why rows are claimed before sending]]
RSpec.describe DigestOrgNotificationAggregator do
  include_context "Setup"

  def setup_notifiable_user(user)
    user.update_columns(sms_notifications_enabled: true, is_phone_verified: true)
    create(:notification_preference, user: user, key: "org_position_taken", enabled: true)
    user
  end

  describe ".enqueue" do
    it "creates a pending digest entry with the expected attributes" do
      _locale, user = setup
      org = create(:organization)
      bill = create(:bill)

      entry = described_class.enqueue(
        user_id: user.id,
        cadence: :daily,
        org_id: org.id,
        bill_id: bill.id,
        change_types: [:new_position, :summary_change]
      )

      expect(entry).to be_persisted
      expect(entry.user_id).to eq(user.id)
      expect(entry.cadence).to eq("daily")
      expect(entry.org_id).to eq(org.id)
      expect(entry.bill_id).to eq(bill.id)
      expect(entry.change_types).to eq("new_position,summary_change")
    end
  end

  describe ".dispatch_period" do
    it "returns early and performs no deliveries when the queue is empty" do
      expect(OrgNotificationFanout).not_to receive(:deliver)
      expect(User).not_to receive(:where)

      described_class.dispatch_period(:daily)
    end

    it "aggregates multiple organization entries for a single user into one digest" do
      _locale, user = setup
      setup_notifiable_user(user)
      org1 = create(:organization, name: "Clean Water Action")
      org2 = create(:organization, name: "Bike Maryland")
      bill = create(:bill)

      described_class.enqueue(
        user_id: user.id, cadence: :daily, org_id: org1.id,
        bill_id: bill.id, change_types: [:new_position]
      )
      described_class.enqueue(
        user_id: user.id, cadence: :daily, org_id: org2.id,
        bill_id: bill.id, change_types: [:new_position]
      )

      expect(OrgNotificationFanout).to receive(:deliver).with(
        user: user,
        title: "Clean Water Action",
        body: "Clean Water Action and 1 other organization updated their positions today.",
        url: "/organizations"
      ).once

      described_class.dispatch_period(:daily)

      expect(PendingOrganizationDigestEntry.where(user_id: user.id, cadence: "daily").count).to eq(0)
    end

    it "paginates across distinct recipients using keyset traversal when batch_size is exceeded" do
      org = create(:organization, name: "Test organization")
      bill = create(:bill)

      users = Array.new(5) { setup_notifiable_user(create(:user, is_registration_complete: true)) }.sort_by(&:id)

      users.each do |user|
        described_class.enqueue(
          user_id: user.id, cadence: :daily, org_id: org.id,
          bill_id: bill.id, change_types: [:new_position]
        )
      end

      delivered_users = []
      allow(OrgNotificationFanout).to receive(:deliver) do |args|
        delivered_users << args[:user]
      end

      # Run with batch_size: 2 to force 3 distinct keyset batches (2 + 2 + 1)
      described_class.dispatch_period(:daily, batch_size: 2)

      expect(delivered_users.map(&:id)).to eq(users.map(&:id))
      expect(PendingOrganizationDigestEntry.where(cadence: "daily").count).to eq(0)
    end

    it "processes a single recipient with entries across multiple orgs into exactly one digest during batched run" do
      org1 = create(:organization, name: "Org Alpha")
      org2 = create(:organization, name: "Org Beta")
      bill = create(:bill)

      user1 = setup_notifiable_user(create(:user, is_registration_complete: true))
      user2 = setup_notifiable_user(create(:user, is_registration_complete: true))

      # user1 has 3 entries from 2 orgs
      described_class.enqueue(user_id: user1.id, cadence: :daily, org_id: org1.id, bill_id: bill.id, change_types: [:new_position])
      described_class.enqueue(user_id: user1.id, cadence: :daily, org_id: org2.id, bill_id: bill.id, change_types: [:support_change])
      described_class.enqueue(user_id: user1.id, cadence: :daily, org_id: org1.id, bill_id: bill.id, change_types: [:summary_change])

      # user2 has 1 entry
      described_class.enqueue(user_id: user2.id, cadence: :daily, org_id: org2.id, bill_id: bill.id, change_types: [:new_position])

      deliveries_by_user = Hash.new(0)
      allow(OrgNotificationFanout).to receive(:deliver) do |args|
        deliveries_by_user[args[:user].id] += 1
      end

      described_class.dispatch_period(:daily, batch_size: 1)

      expect(deliveries_by_user[user1.id]).to eq(1)
      expect(deliveries_by_user[user2.id]).to eq(1)
      expect(PendingOrganizationDigestEntry.where(cadence: "daily").count).to eq(0)
    end

    it "handles high row counts spanning SQLite slice boundaries (1,050 entries for one recipient)" do
      user = setup_notifiable_user(create(:user, is_registration_complete: true))
      org = create(:organization, name: "Big Data Org")
      bill = create(:bill)

      now = Time.current
      entries = Array.new(1050) do |i|
        {
          user_id: user.id,
          cadence: "daily",
          org_id: org.id,
          bill_id: bill.id,
          change_types: "new_position",
          created_at: now + i.seconds,
          updated_at: now + i.seconds
        }
      end
      PendingOrganizationDigestEntry.insert_all!(entries)

      expect(OrgNotificationFanout).to receive(:deliver).with(
        user: user,
        title: "Big Data Org",
        body: "Big Data Org updated their positions today.",
        url: "/organizations"
      ).once

      described_class.dispatch_period(:daily)

      expect(PendingOrganizationDigestEntry.where(user_id: user.id).count).to eq(0)
    end

    it "skips delivery when entries are claimed by a concurrent process (deleted_count is zero)" do
      user = setup_notifiable_user(create(:user, is_registration_complete: true))
      org = create(:organization)
      bill = create(:bill)

      described_class.enqueue(
        user_id: user.id, cadence: :daily, org_id: org.id,
        bill_id: bill.id, change_types: [:new_position]
      )

      # Simulate race: another worker deletes the rows right after batch_entries were loaded
      # but before this worker's claim transaction executes
      original_where = PendingOrganizationDigestEntry.method(:where)
      allow(PendingOrganizationDigestEntry).to receive(:where) do |*args, **kwargs|
        relation = original_where.call(*args, **kwargs)
        if kwargs.key?(:id)
          # Pre-delete rows so delete_all returns 0
          relation.delete_all
        end
        relation
      end

      expect(OrgNotificationFanout).not_to receive(:deliver)

      described_class.dispatch_period(:daily)
    end

    it "isolates cadences so daily dispatch does not touch or deliver weekly entries" do
      user = setup_notifiable_user(create(:user, is_registration_complete: true))
      org = create(:organization)
      bill = create(:bill)

      described_class.enqueue(
        user_id: user.id, cadence: :weekly, org_id: org.id,
        bill_id: bill.id, change_types: [:new_position]
      )

      expect(OrgNotificationFanout).not_to receive(:deliver)

      described_class.dispatch_period(:daily)

      expect(PendingOrganizationDigestEntry.where(user_id: user.id, cadence: "weekly").count).to eq(1)
    end

    it "is idempotent on repeated runs" do
      user = setup_notifiable_user(create(:user, is_registration_complete: true))
      org = create(:organization)
      bill = create(:bill)

      described_class.enqueue(
        user_id: user.id, cadence: :daily, org_id: org.id,
        bill_id: bill.id, change_types: [:new_position]
      )

      expect(OrgNotificationFanout).to receive(:deliver).once

      described_class.dispatch_period(:daily)
      described_class.dispatch_period(:daily)
    end

    it "purges orphaned pending entries whose user record no longer exists without delivery" do
      org = create(:organization)
      bill = create(:bill)

      PendingOrganizationDigestEntry.insert!({
        user_id: 888_777,
        cadence: "daily",
        org_id: org.id,
        bill_id: bill.id,
        change_types: "new_position",
        created_at: Time.current,
        updated_at: Time.current
      })

      expect(OrgNotificationFanout).not_to receive(:deliver)

      described_class.dispatch_period(:daily)

      expect(PendingOrganizationDigestEntry.where(user_id: 888_777).count).to eq(0)
    end

    it "purges entries and skips delivery when user has disabled org_position_taken preference" do
      user = create(:user, is_registration_complete: true)
      create(:notification_preference, user: user, key: "org_position_taken", enabled: false)
      org = create(:organization)
      bill = create(:bill)

      described_class.enqueue(
        user_id: user.id, cadence: :daily, org_id: org.id,
        bill_id: bill.id, change_types: [:new_position]
      )

      expect(OrgNotificationFanout).not_to receive(:deliver)

      described_class.dispatch_period(:daily)

      expect(PendingOrganizationDigestEntry.where(user_id: user.id).count).to eq(0)
    end

    it "purges entries and skips delivery when all referenced organizations have been deleted" do
      user = setup_notifiable_user(create(:user, is_registration_complete: true))
      org = create(:organization)
      bill = create(:bill)

      described_class.enqueue(
        user_id: user.id, cadence: :daily, org_id: org.id,
        bill_id: bill.id, change_types: [:new_position]
      )

      org.delete

      expect(OrgNotificationFanout).not_to receive(:deliver)

      described_class.dispatch_period(:daily)

      expect(PendingOrganizationDigestEntry.where(user_id: user.id).count).to eq(0)
    end

    it "preloads organizations in a single query per batch to avoid N+1 queries" do
      org1 = create(:organization, name: "Org 1")
      org2 = create(:organization, name: "Org 2")
      bill = create(:bill)

      users = Array.new(3) { setup_notifiable_user(create(:user, is_registration_complete: true)) }
      users.each do |user|
        described_class.enqueue(user_id: user.id, cadence: :daily, org_id: org1.id, bill_id: bill.id, change_types: [:new_position])
        described_class.enqueue(user_id: user.id, cadence: :daily, org_id: org2.id, bill_id: bill.id, change_types: [:new_position])
      end

      org_query_count = 0
      query_recorder = lambda do |_name, _start, _finish, _id, payload|
        if payload[:sql].match?(/\bFROM\s+["`]?organizations["`]?\b/i)
          org_query_count += 1
        end
      end

      ActiveSupport::Notifications.subscribed(query_recorder, "sql.active_record") do
        described_class.dispatch_period(:daily, batch_size: 10)
      end

      # For 3 users in 1 batch, Organization should be queried exactly once, not 3 times (no N+1)
      expect(org_query_count).to eq(1)
    end
  end

  describe ".build_digest_copy" do
    it "formats copy for a single organization" do
      title, body = described_class.send(:build_digest_copy, ["Sway Advocacy"], 1, "today")
      expect(title).to eq("Sway Advocacy")
      expect(body).to eq("Sway Advocacy updated their positions today.")
    end

    it "formats copy for two organizations" do
      title, body = described_class.send(:build_digest_copy, ["Sway Advocacy", "Clean Water Action"], 2, "this week")
      expect(title).to eq("Sway Advocacy")
      expect(body).to eq("Sway Advocacy and 1 other organization updated their positions this week.")
    end

    it "formats copy for three or more organizations" do
      title, body = described_class.send(:build_digest_copy, ["Sway Advocacy", "Clean Water Action", "Bike MD"], 3, "today")
      expect(title).to eq("Sway Advocacy")
      expect(body).to eq("Sway Advocacy and 2 other organizations updated their positions today.")
    end
  end
end
