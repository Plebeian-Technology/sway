# frozen_string_literal: true

# Phase 61 WR-04 — durable per-(position, change-types, user) sent-marker so a
# retried/replayed NotifyOrganizationFollowersJob cannot re-send immediate
# web/native push or billable SMS to an already-notified every_change follower.
# The unique index is the idempotency guard: the first delivery inserts the
# marker, a replay raises RecordNotUnique and is skipped.
#
# No DB foreign key (mirrors pending_org_digest_entries) — User#destroy purges
# rows via has_many :org_notification_deliveries, dependent: :destroy.
class CreateOrgNotificationDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :org_notification_deliveries do |t|
      t.integer :organization_bill_position_id, null: false
      t.integer :user_id, null: false
      # Sorted, comma-joined change_types (e.g. "new_position" or
      # "support_change,summary_change") — distinguishes legitimately-separate
      # bursts for the same (position, user) from a re-sent duplicate.
      t.string :change_type, null: false
      t.datetime :created_at, null: false
    end

    add_index :org_notification_deliveries,
      %i[organization_bill_position_id user_id change_type],
      unique: true,
      name: "idx_org_notif_deliveries_unique"
    add_index :org_notification_deliveries, :user_id,
      name: "index_org_notification_deliveries_on_user_id"
  end
end
