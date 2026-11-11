# frozen_string_literal: true

# Phase 61 Plan 01 (REQ-1 / D-15) — add per-follow preference columns to
# organization_follows. All columns have NOT NULL + DEFAULT so existing rows
# receive a valid value immediately — no separate backfill needed.
# Enum mapping (LOCKED across organization_follows + users so seed_attrs_from
# can copy user default int → follow int):
#   0: every_change, 1: daily, 2: weekly
class AddPreferencesToOrganizationFollows < ActiveRecord::Migration[8.1]
  def change
    add_column :organization_follows, :notification_cadence, :integer,
               null: false, default: 0  # 0 = every_change, 1 = daily, 2 = weekly

    add_column :organization_follows, :notify_on_new_position, :boolean,
               null: false, default: true

    add_column :organization_follows, :notify_on_support_change, :boolean,
               null: false, default: true

    add_column :organization_follows, :notify_on_summary_change, :boolean,
               null: false, default: true
  end
end
