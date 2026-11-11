class CreateUserBillReminders < ActiveRecord::Migration[8.0]
  def change
    create_table :user_bill_reminders do |t|
      t.references :user, null: false, foreign_key: true
      t.references :bill, null: false, foreign_key: true
      t.datetime :sent_at

      t.timestamps
    end
  end
end
