# frozen_string_literal: true

# WS5.17 — the users.is_admin boolean column was dead. Admin authorization
# flows exclusively through User#is_sway_admin? (the ADMIN_PHONES allowlist);
# the column was written `false` in before_create and never read for authz.
# The before_create write and the split-brain #as_json that stripped the column
# are removed in the same commit. The frontend still receives the DERIVED
# `is_admin` JSON key from User#to_builder (is_sway_admin?), so index.d.ts and
# AuthLayout are unaffected.
#
# Reversible: db:rollback re-adds the column with its original default.
class DropUsersIsAdmin < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :is_admin, :boolean, default: false
  end
end
