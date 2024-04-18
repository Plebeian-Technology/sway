class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :email
      t.boolean :is_email_verified

      t.string :phone
      t.boolean :is_phone_verified

      t.boolean :is_registration_complete
      t.boolean :is_registered_to_vote
      t.boolean :is_admin, :default => false

      t.references :address, null: false, foreign_key: true

      t.timestamps
    end

    add_index :users, :email,                unique: true
    add_index :users, :confirmation_token,   unique: true
  end
end
