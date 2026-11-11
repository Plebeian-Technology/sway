# frozen_string_literal: true

# Phase 60 Plan 01 (R1): global topical taxonomy table.
# NO sway_locale_id FK — the Category taxonomy is jurisdiction-agnostic
# (a bill tagged "Health" is "Health" regardless of locale).
class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :categories, :slug, unique: true
    add_index :categories, :active
  end
end
