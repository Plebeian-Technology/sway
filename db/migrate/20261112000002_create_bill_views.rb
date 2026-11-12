# frozen_string_literal: true

class CreateBillViews < ActiveRecord::Migration[8.1]
  def change
    create_table :bill_views do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :bill, null: false, foreign_key: true

      t.timestamps

      t.index [:user_id, :bill_id], unique: true
    end
  end
end
