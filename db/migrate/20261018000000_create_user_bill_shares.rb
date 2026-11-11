# frozen_string_literal: true

class CreateUserBillShares < ActiveRecord::Migration[8.1]
  def change
    create_table :user_bill_shares do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :bill, null: false, foreign_key: true
      t.string :share_uuid, null: false
      t.datetime :redeemed_at

      t.timestamps

      t.index [:user_id, :bill_id], unique: true
      t.index :share_uuid, unique: true
    end
  end
end
