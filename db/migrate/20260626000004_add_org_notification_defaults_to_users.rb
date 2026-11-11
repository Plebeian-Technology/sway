# frozen_string_literal: true

# Phase 61 Plan 01 (REQ-5 / D-15) — global org-notification defaults on User.
# NOT NULL with DB defaults: on-insert existing rows pick up the default
# without a backfill migration.
# Enum mapping (LOCKED — must match organization_follows.notification_cadence):
#   0: every_change, 1: daily, 2: weekly
class AddOrgNotificationDefaultsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :org_position_cadence_default, :integer,
               null: false, default: 0  # 0 = every_change, 1 = daily, 2 = weekly

    add_column :users, :notify_on_new_position_default, :boolean,
               null: false, default: true

    add_column :users, :notify_on_support_change_default, :boolean,
               null: false, default: true

    add_column :users, :notify_on_summary_change_default, :boolean,
               null: false, default: true
  end
end
