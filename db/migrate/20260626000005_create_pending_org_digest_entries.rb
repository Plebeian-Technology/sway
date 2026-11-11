# frozen_string_literal: true

# Phase 61 Plan 07 (D-17 / REQ-10) — durable pending digest queue.
# Rows are written by DigestOrgNotificationAggregator.enqueue when
# NotifyOrganizationFollowersService routes a daily/weekly follower.
# Rows are deleted by dispatch_period after a digest is sent.
# Survives Pi restarts (Pi durability constraint).
class CreatePendingOrgDigestEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :pending_org_digest_entries do |t|
      t.integer :user_id, null: false
      t.string :cadence, null: false
      t.integer :org_id, null: false
      t.integer :bill_id, null: false
      t.string :change_types, null: false
      t.timestamps

      # Primary dispatch_period window query: WHERE cadence = ? AND created_at >= ?
      t.index [:cadence, :created_at], name: "idx_pending_org_digest_on_cadence_created_at"
      # Secondary grouping: after loading the period rows, group by user_id
      t.index :user_id, name: "index_pending_org_digest_entries_on_user_id"
    end
  end
end
