# frozen_string_literal: true

class CreateUserDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :user_devices do |t|
      t.references :user, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :push_token
      t.string :app_version
      t.datetime :last_seen_at, null: false
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :user_devices, :push_token
    add_index :user_devices, [:user_id, :revoked_at]
    add_index :user_devices,
      :push_token,
      unique: true,
      where: "revoked_at IS NULL",
      name: "index_user_devices_on_push_token_active"
  end
end
