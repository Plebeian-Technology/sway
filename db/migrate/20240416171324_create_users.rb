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

      ## Rememberable
      t.datetime :remember_created_at

      ## Trackable
      t.integer  :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at_utc
      t.datetime :last_sign_in_at_utc
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      ## Confirmable
      t.string :unconfirmed_email
      t.string   :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at

      t.references :address, null: false, foreign_key: true

      t.timestamps
    end

    add_index :users, :email,                unique: true
    add_index :users, :confirmation_token,   unique: true
  end
end
