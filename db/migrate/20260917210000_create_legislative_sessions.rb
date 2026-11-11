# frozen_string_literal: true

class CreateLegislativeSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :legislative_sessions do |t|
      t.references :sway_locale, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.boolean :active, default: false, null: false

      t.timestamps
    end

    add_index :legislative_sessions, [:sway_locale_id, :name], unique: true
    add_index :legislative_sessions, [:sway_locale_id, :active]
  end
end
