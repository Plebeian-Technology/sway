# frozen_string_literal: true

# Phase 61 pass-2 review (Critical) — add a per-EVENT discriminator to the
# immediate-notification sent-marker.
#
# The original WR-04 unique index was (organization_bill_position_id, user_id,
# change_type). A position row is created once per (bill, org) and its
# support/summary are UPDATED in place, so the marker key had NO temporal/event
# dimension: a genuinely-later same-type change (e.g. an org reversing its stance
# a second time) produced the IDENTICAL key as the first, hit the unique index,
# and was silently suppressed forever — breaking the platform's headline
# accountability feature for every_change followers.
#
# `delivery_token` is the triggering change's updated_at (iso8601, microseconds),
# captured at the enqueue site and threaded through the job so retries of the SAME
# burst carry the SAME token (still collide → no double-send), while a distinct
# later change carries a NEW token (delivers). An unchanged re-submit no-ops the
# upsert, so updated_at — and thus the token — does not advance (still suppressed).
class AddDeliveryTokenToOrgNotificationDeliveries < ActiveRecord::Migration[8.1]
  def up
    # Sent-markers are transient idempotency rows; clearing them at the schema
    # boundary is safe (at worst one duplicate notification, one-time) and avoids
    # backfilling a NOT NULL token for legacy rows that predate the discriminator.
    execute "DELETE FROM org_notification_deliveries"

    remove_index :org_notification_deliveries, name: "idx_org_notif_deliveries_unique"
    # Add nullable then enforce NOT NULL via change_column_null: the table was just
    # emptied above, so there are no NULL rows to violate the constraint, and this
    # avoids a bogus column default (a delivery token is always set explicitly by
    # the app — there is no meaningful default value for it).
    add_column :org_notification_deliveries, :delivery_token, :string
    change_column_null :org_notification_deliveries, :delivery_token, false
    add_index :org_notification_deliveries,
      %i[organization_bill_position_id user_id change_type delivery_token],
      unique: true,
      name: "idx_org_notif_deliveries_unique"
  end

  def down
    remove_index :org_notification_deliveries, name: "idx_org_notif_deliveries_unique"
    remove_column :org_notification_deliveries, :delivery_token
    add_index :org_notification_deliveries,
      %i[organization_bill_position_id user_id change_type],
      unique: true,
      name: "idx_org_notif_deliveries_unique"
  end
end
