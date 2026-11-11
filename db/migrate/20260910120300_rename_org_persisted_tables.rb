# frozen_string_literal: true

class RenameOrgPersistedTables < ActiveRecord::Migration[8.1]
  def change
    rename_table :org_notification_deliveries, :organization_notification_deliveries
    rename_table :pending_org_digest_entries, :pending_organization_digest_entries
  end
end
