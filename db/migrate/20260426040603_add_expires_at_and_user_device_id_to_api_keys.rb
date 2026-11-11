# frozen_string_literal: true

class AddExpiresAtAndUserDeviceIdToApiKeys < ActiveRecord::Migration[8.1]
  def change
    add_column :api_keys, :expires_at, :datetime
    add_reference :api_keys, :user_device, foreign_key: true, null: true
    add_index :api_keys, :expires_at
  end
end
