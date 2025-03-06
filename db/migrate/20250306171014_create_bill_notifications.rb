class CreateBillNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :bill_notifications do |t|
      t.references :bill, null: false, foreign_key: true, index: {unique: true}

      t.timestamps
    end
  end
end
