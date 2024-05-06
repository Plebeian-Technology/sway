# typed: true
class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :email
      t.boolean :is_email_verified

      t.string :phone
      t.boolean :is_phone_verified

      t.boolean :is_registration_complete
      t.boolean :is_registered_to_vote
      t.boolean :is_admin, default: false

      t.string :webauthn_id

      # Trackable
      t.integer  :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      t.references :address, null: true, foreign_key: true

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :phone, unique: true
    add_index :users, :webauthn_id, unique: true
  end
end
