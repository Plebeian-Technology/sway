# frozen_string_literal: true

class CreateUserAddressChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :user_address_changes do |t|
      t.references :user, null: false, foreign_key: {to_table: :users, on_delete: :cascade}
      t.integer :previous_address_id, null: false
      t.integer :new_address_id, null: false
      t.json :deactivated_legislator_ids, null: false, default: []
      t.json :activated_legislator_ids, null: false, default: []
      t.json :deactivated_district_ids, null: false, default: []
      t.json :activated_district_ids, null: false, default: []
      t.json :previous_sway_locale_ids, null: false, default: []
      t.json :new_sway_locale_ids, null: false, default: []
      t.integer :prior_vote_count, null: false, default: 0
      t.json :prior_voted_bill_ids, null: false, default: []
      t.json :prior_voted_sway_locale_ids, null: false, default: []

      t.timestamps

      t.index [:user_id, :created_at]
      t.index :created_at
      t.index :previous_address_id
      t.index :new_address_id
    end
  end
end
