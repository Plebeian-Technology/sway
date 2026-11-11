# frozen_string_literal: true

# Phase 65 (D-12/R7): recreates user_districts as a fresh table, distinct
# from the one 20260705000003 already dropped (that old table had no
# `active` column and no production write path — see WS2.5). This new
# incarnation gives the reconcile job (R7) a stored, diffable fact for
# "district changed vs seat occupant changed": a user keeps one row per
# district they've ever been assigned to, with `active` toggled rather than
# rows being deleted, so reassignment history is preserved.
#
# Timestamped after 20260705000003 (the drop) so db:reset applies the old
# drop, then this create, with no "table already exists" collision
# (RESEARCH Pitfall 3). Does not edit or duplicate the drop migration.
class RecreateUserDistrictsWithActiveFlag < ActiveRecord::Migration[8.1]
  def change
    create_table :user_districts do |t|
      t.integer :user_id, null: false
      t.integer :district_id, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :user_districts, [:user_id, :district_id], unique: true
    add_foreign_key :user_districts, :users
    add_foreign_key :user_districts, :districts
  end
end
