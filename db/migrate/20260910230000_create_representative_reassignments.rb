# frozen_string_literal: true

class CreateRepresentativeReassignments < ActiveRecord::Migration[8.1]
  def change
    create_table :representative_reassignments do |t|
      t.references :user, null: false, foreign_key: {on_delete: :cascade}, index: true
      t.references :district, null: true, foreign_key: true, index: true
      t.references :previous_district, null: true, foreign_key: {to_table: :districts}
      t.references :legislator, null: true, foreign_key: true, index: true
      t.references :previous_legislator, null: true, foreign_key: {to_table: :legislators}
      t.integer :reassignment_type, null: false, default: 0
      t.datetime :notified_at, null: true
      t.datetime :dismissed_at, null: true

      t.timestamps
    end

    add_index :representative_reassignments,
      [:user_id, :district_id, :legislator_id, :previous_legislator_id],
      unique: true,
      where: "previous_legislator_id IS NOT NULL AND legislator_id IS NOT NULL",
      name: "idx_rep_reassign_full_unique"

    add_index :representative_reassignments,
      [:user_id, :district_id, :previous_legislator_id],
      unique: true,
      where: "legislator_id IS NULL",
      name: "idx_rep_reassign_vacant_unique"

    add_index :representative_reassignments,
      [:user_id, :district_id, :legislator_id],
      unique: true,
      where: "previous_legislator_id IS NULL",
      name: "idx_rep_reassign_filled_unique"

    add_index :representative_reassignments,
      [:user_id, :dismissed_at],
      name: "idx_rep_reassign_user_active"
  end
end
