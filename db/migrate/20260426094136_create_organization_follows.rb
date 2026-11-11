# frozen_string_literal: true

# Phase 32 Plan 09 — Public Organizations + follow/unfollow (D-08).
#
# OrganizationFollow tracks which Organizations a User follows. The composite
# unique index [user_id, organization_id] backs OrganizationFollowsController's
# `find_or_create_by!` and the controller's idempotency contract (T-32-09-02).
class CreateOrganizationFollows < ActiveRecord::Migration[8.1]
  def change
    create_table :organization_follows do |t|
      t.references :user, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.timestamps
    end
    add_index :organization_follows, [:user_id, :organization_id], unique: true, name: "idx_organization_follows_on_user_and_organization"
  end
end
