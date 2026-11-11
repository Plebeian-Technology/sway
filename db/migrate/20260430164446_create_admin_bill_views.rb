# frozen_string_literal: true

# @lat: [[client-caches-and-identity#Client caches and identity#Why last-seen state moved off the cookie]]
class CreateAdminBillViews < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_bill_views do |t|
      t.references :admin_user, null: false, foreign_key: {to_table: :users}
      t.references :bill, null: false, foreign_key: true
      t.datetime :last_seen_at, null: false

      t.timestamps
    end

    add_index :admin_bill_views,
      [:admin_user_id, :bill_id],
      unique: true,
      name: "index_admin_bill_views_on_admin_user_and_bill"
  end
end
