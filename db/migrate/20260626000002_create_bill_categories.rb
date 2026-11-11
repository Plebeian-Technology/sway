# frozen_string_literal: true

# Phase 60 Plan 01 (R2): join table linking bills to their topical categories.
# The unique composite index on (bill_id, category_id) is the collision safety
# net for find_or_create_by! races in BillCategoryAssigner (later waves).
class CreateBillCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :bill_categories do |t|
      t.references :bill, null: false, foreign_key: true, index: true
      t.references :category, null: false, foreign_key: true, index: true

      t.timestamps
    end

    add_index :bill_categories, [:bill_id, :category_id], unique: true
  end
end
