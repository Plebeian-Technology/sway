# frozen_string_literal: true

class CreateNotificationPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.string :key, null: false
      t.boolean :enabled, null: false, default: false

      t.timestamps
    end

    add_index :notification_preferences, [:user_id, :key], unique: true
  end
end
