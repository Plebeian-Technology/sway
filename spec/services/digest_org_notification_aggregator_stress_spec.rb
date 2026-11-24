# frozen_string_literal: true

require "rails_helper"

# Adversarial Stress Test Suite for:
# Bound digest dispatch memory by recipient
#
# @lat: [[pending-org-digest-entry-design#Why PendingOrganizationDigestEntry is a durable queue]]
# @lat: [[pending-org-digest-entry-design#Why dispatch_period uses keyset pagination by recipient]]
# @lat: [[pending-org-digest-entry-design#Why rows are claimed before sending]]
RSpec.describe "DigestOrgNotificationAggregator Adversarial Stress Harness" do
  include_context "Setup"

  def setup_notifiable_user(user)
    user.update_columns(sms_notifications_enabled: true, is_phone_verified: true)
    create(:notification_preference, user: user, key: "org_position_taken", enabled: true)
    user
  end

  describe "1. Multi-batch keyset traversal with cursor progression" do
    it "traverses 23 users across uneven batch sizes (batch_size: 5 -> 5, 5, 5, 5, 3) without skips or duplicates" do
      org = create(:organization, name: "Empirical Civic Alliance")
      bill = create(:bill)

      users = Array.new(23) do
        setup_notifiable_user(create(:user, is_registration_complete: true))
      end.sort_by(&:id)

      users.each_with_index do |user, idx|
        # Varying entries per user (1 to 4 entries)
        (idx % 4 + 1).times do
          DigestOrgNotificationAggregator.enqueue(
            user_id: user.id,
            cadence: :daily,
            org_id: org.id,
            bill_id: bill.id,
            change_types: [:new_position]
          )
        end
      end

      delivered_uids = []
      allow(OrgNotificationFanout).to receive(:deliver) do |args|
        delivered_uids << args[:user].id
      end

      # 23 users with batch_size: 5 forces 5 distinct loop iterations
      DigestOrgNotificationAggregator.dispatch_period(:daily, batch_size: 5)

      expect(delivered_uids).to eq(users.map(&:id))
      expect(PendingOrganizationDigestEntry.where(cadence: "daily").count).to eq(0)
    end

    it "handles sparse, non-contiguous user_id keysets correctly" do
      org = create(:organization, name: "Open Gov League")
      bill = create(:bill)

      sparse_ids = [11, 88, 305, 999, 4444, 12345]
      sparse_users = sparse_ids.map do |uid|
        u = create(:user, is_registration_complete: true, id: uid)
        setup_notifiable_user(u)
      end.sort_by(&:id)

      sparse_users.each do |user|
        DigestOrgNotificationAggregator.enqueue(
          user_id: user.id,
          cadence: :daily,
          org_id: org.id,
          bill_id: bill.id,
          change_types: [:new_position]
        )
      end

      delivered_uids = []
      allow(OrgNotificationFanout).to receive(:deliver) do |args|
        delivered_uids << args[:user].id
      end

      DigestOrgNotificationAggregator.dispatch_period(:daily, batch_size: 2)

      expect(delivered_uids).to eq(sparse_users.map(&:id))
      expect(PendingOrganizationDigestEntry.where(cadence: "daily").count).to eq(0)
    end

    it "terminates cleanly when total recipient count is an exact multiple of batch_size" do
      org = create(:organization, name: "Exact Multiple Org")
      bill = create(:bill)

      users = Array.new(6) do
        setup_notifiable_user(create(:user, is_registration_complete: true))
      end.sort_by(&:id)

      users.each do |user|
        DigestOrgNotificationAggregator.enqueue(
          user_id: user.id,
          cadence: :daily,
          org_id: org.id,
          bill_id: bill.id,
          change_types: [:new_position]
        )
      end

      delivered_uids = []
      allow(OrgNotificationFanout).to receive(:deliver) do |args|
        delivered_uids << args[:user].id
      end

      # Exactly 6 users with batch_size 3 => iterations: [3], [3], then [0] -> break
      DigestOrgNotificationAggregator.dispatch_period(:daily, batch_size: 3)

      expect(delivered_uids).to eq(users.map(&:id))
      expect(PendingOrganizationDigestEntry.where(cadence: "daily").count).to eq(0)
    end
  end

  describe "2. Sliced transactional deletion for user with >1,000 pending entries" do
    it "processes 2,500 pending entries for a single recipient across 3 slices (1000, 1000, 500)" do
      user = setup_notifiable_user(create(:user, is_registration_complete: true))
      org = create(:organization, name: "Mass Notification Watch")
      bill = create(:bill)

      now = Time.current
      entries = Array.new(2500) do |i|
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

      expect(PendingOrganizationDigestEntry.where(user_id: user.id, cadence: "daily").count).to eq(2500)

      delivery_count = 0
      allow(OrgNotificationFanout).to receive(:deliver) do |args|
        expect(args[:user].id).to eq(user.id)
        expect(args[:title]).to eq("Organization update")
        expect(args[:body]).to eq("Sway recorded new positions from Mass Notification Watch today.")
        delivery_count += 1
      end

      DigestOrgNotificationAggregator.dispatch_period(:daily)

      expect(delivery_count).to eq(1)
      expect(PendingOrganizationDigestEntry.where(user_id: user.id, cadence: "daily").count).to eq(0)
    end

    it "rolls back entire claim transaction if an exception occurs on a subsequent slice" do
      user = setup_notifiable_user(create(:user, is_registration_complete: true))
      org = create(:organization, name: "Atomic Rollback Org")
      bill = create(:bill)

      now = Time.current
      entries = Array.new(1500) do |i|
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

      call_count = 0
      original_where = PendingOrganizationDigestEntry.method(:where)
      allow(PendingOrganizationDigestEntry).to receive(:where) do |*args, **kwargs|
        rel = original_where.call(*args, **kwargs)
        if kwargs.key?(:id) && kwargs[:id].is_a?(Array)
          call_count += 1
          # Fail on the second slice inside the transaction
          raise ActiveRecord::StatementInvalid, "Simulated transient SQLite disk/lock error" if call_count == 2
        end
        rel
      end

      expect do
        DigestOrgNotificationAggregator.dispatch_period(:daily)
      end.to raise_error(ActiveRecord::StatementInvalid, /Simulated transient SQLite/)

      # Because the claim was inside a transaction, slice 1 must be rolled back!
      expect(PendingOrganizationDigestEntry.where(user_id: user.id, cadence: "daily").count).to eq(1500)
    end
  end

  describe "3. Simulation of concurrent worker claims (deleted_count is 0)" do
    it "skips delivery when deleted_count is 0 due to concurrent claim" do
      user = setup_notifiable_user(create(:user, is_registration_complete: true))
      org = create(:organization, name: "Concurrent Race Org")
      bill = create(:bill)

      DigestOrgNotificationAggregator.enqueue(
        user_id: user.id,
        cadence: :daily,
        org_id: org.id,
        bill_id: bill.id,
        change_types: [:new_position]
      )

      # Simulate another worker deleting the rows concurrently before our claim transaction runs
      original_where = PendingOrganizationDigestEntry.method(:where)
      allow(PendingOrganizationDigestEntry).to receive(:where) do |*args, **kwargs|
        rel = original_where.call(*args, **kwargs)
        if kwargs.key?(:id)
          # Concurrent worker pre-emptively deleted the rows
          rel.delete_all
        end
        rel
      end

      expect(OrgNotificationFanout).not_to receive(:deliver)

      DigestOrgNotificationAggregator.dispatch_period(:daily)
    end

    it "guarantees at-most-once delivery across concurrent dispatch executions" do
      org = create(:organization, name: "Multi-Thread Org")
      bill = create(:bill)

      users = Array.new(10) do
        setup_notifiable_user(create(:user, is_registration_complete: true))
      end

      users.each do |user|
        DigestOrgNotificationAggregator.enqueue(
          user_id: user.id,
          cadence: :daily,
          org_id: org.id,
          bill_id: bill.id,
          change_types: [:new_position]
        )
      end

      deliveries = Concurrent::Array.new
      allow(OrgNotificationFanout).to receive(:deliver) do |args|
        deliveries << args[:user].id
      end

      # Run two concurrent threads simulating overlapping background jobs
      t1 = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          DigestOrgNotificationAggregator.dispatch_period(:daily, batch_size: 3)
        end
      end

      t2 = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          DigestOrgNotificationAggregator.dispatch_period(:daily, batch_size: 3)
        end
      end

      t1.join
      t2.join

      # Every user must be delivered at most once (no duplicates)
      expect(deliveries.size).to eq(10)
      expect(deliveries.uniq.size).to eq(10)
      expect(PendingOrganizationDigestEntry.where(cadence: "daily").count).to eq(0)
    end
  end

  describe "4. Empty queue, disabled preferences, deleted users, and deleted orgs" do
    it "handles empty queue without performing any queries beyond initial check" do
      expect(OrgNotificationFanout).not_to receive(:deliver)
      expect(User).not_to receive(:where)
      expect(NotificationPreference).not_to receive(:where)
      expect(Organization).not_to receive(:where)

      DigestOrgNotificationAggregator.dispatch_period(:daily)
    end

    it "purges entries for deleted users, disabled preferences, and deleted orgs in a mixed batch" do
      bill = create(:bill)
      org_alive = create(:organization, name: "Alive Org")
      org_to_delete = create(:organization, name: "Dead Org")

      # User 1: Valid and active
      u1 = setup_notifiable_user(create(:user, is_registration_complete: true))
      DigestOrgNotificationAggregator.enqueue(
        user_id: u1.id, cadence: :daily, org_id: org_alive.id, bill_id: bill.id, change_types: [:new_position]
      )

      # User 2: Notification preference explicitly disabled
      u2 = create(:user, is_registration_complete: true)
      create(:notification_preference, user: u2, key: "org_position_taken", enabled: false)
      DigestOrgNotificationAggregator.enqueue(
        user_id: u2.id, cadence: :daily, org_id: org_alive.id, bill_id: bill.id, change_types: [:new_position]
      )

      # User 3: Notification preference missing entirely
      u3 = create(:user, is_registration_complete: true)
      DigestOrgNotificationAggregator.enqueue(
        user_id: u3.id, cadence: :daily, org_id: org_alive.id, bill_id: bill.id, change_types: [:new_position]
      )

      # User 4: Deleted user (orphaned entry in pending table)
      dead_uid = 999_888_777
      PendingOrganizationDigestEntry.insert!({
        user_id: dead_uid,
        cadence: "daily",
        org_id: org_alive.id,
        bill_id: bill.id,
        change_types: "new_position",
        created_at: Time.current,
        updated_at: Time.current
      })

      # User 5: User valid, but referenced org is deleted
      u5 = setup_notifiable_user(create(:user, is_registration_complete: true))
      DigestOrgNotificationAggregator.enqueue(
        user_id: u5.id, cadence: :daily, org_id: org_to_delete.id, bill_id: bill.id, change_types: [:new_position]
      )
      org_to_delete.delete

      delivered_uids = []
      allow(OrgNotificationFanout).to receive(:deliver) do |args|
        delivered_uids << args[:user].id
      end

      # Dispatch with batch_size: 10 so all 5 users are in one batch
      DigestOrgNotificationAggregator.dispatch_period(:daily, batch_size: 10)

      # ONLY User 1 should have received a delivery
      expect(delivered_uids).to eq([u1.id])

      # ALL entries for all 5 users must be completely purged
      expect(PendingOrganizationDigestEntry.where(cadence: "daily").count).to eq(0)
    end
  end

  describe "5. Cadence isolation and type handling" do
    it "does not touch or deliver weekly entries during daily dispatch" do
      user = setup_notifiable_user(create(:user, is_registration_complete: true))
      org = create(:organization, name: "Weekly Org")
      bill = create(:bill)

      DigestOrgNotificationAggregator.enqueue(
        user_id: user.id, cadence: :weekly, org_id: org.id, bill_id: bill.id, change_types: [:new_position]
      )

      expect(OrgNotificationFanout).not_to receive(:deliver)

      DigestOrgNotificationAggregator.dispatch_period(:daily)

      expect(PendingOrganizationDigestEntry.where(cadence: "weekly").count).to eq(1)
    end

    it "accepts cadence as a string or a symbol equivalently" do
      user = setup_notifiable_user(create(:user, is_registration_complete: true))
      org = create(:organization, name: "Symbol String Org")
      bill = create(:bill)

      DigestOrgNotificationAggregator.enqueue(
        user_id: user.id, cadence: "daily", org_id: org.id, bill_id: bill.id, change_types: [:new_position]
      )

      expect(OrgNotificationFanout).to receive(:deliver).once

      DigestOrgNotificationAggregator.dispatch_period("daily")

      expect(PendingOrganizationDigestEntry.where(cadence: "daily").count).to eq(0)
    end
  end

  describe "6. Memory and query bounding verification" do
    it "strictly bounds recipient query size to batch_size" do
      org = create(:organization, name: "Batch Bound Org")
      bill = create(:bill)

      users = Array.new(15) do
        setup_notifiable_user(create(:user, is_registration_complete: true))
      end

      users.each do |user|
        DigestOrgNotificationAggregator.enqueue(
          user_id: user.id, cadence: :daily, org_id: org.id, bill_id: bill.id, change_types: [:new_position]
        )
      end

      allow(OrgNotificationFanout).to receive(:deliver)

      user_query_sizes = []
      user_query_recorder = lambda do |_name, _start, _finish, _id, payload|
        sql = payload[:sql]
        if sql.match?(/\bFROM\s+["`]?users["`]?\b/i) && sql.match?(/\bWHERE\s+["`]?users["`]?\.["`]?id["`]?\s+IN/i)
          # Extract count of IDs in IN clause
          in_match = sql.match(/IN\s*\(([^)]+)\)/i)
          if in_match
            ids = in_match[1].split(",")
            user_query_sizes << ids.size
          end
        end
      end

      ActiveSupport::Notifications.subscribed(user_query_recorder, "sql.active_record") do
        DigestOrgNotificationAggregator.dispatch_period(:daily, batch_size: 4)
      end

      # 15 users in batches of 4 => batches of 4, 4, 4, 3
      expect(user_query_sizes).to eq([4, 4, 4, 3])
    end
  end
end
