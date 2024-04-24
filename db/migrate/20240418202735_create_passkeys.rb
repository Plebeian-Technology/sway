# typed: true
class CreatePasskeys < ActiveRecord::Migration[7.1]
  def change
    create_table :passkeys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :label, null: false
      t.string :external_id
      t.string :public_key
      t.integer :sign_count
      t.datetime :last_used_at

      t.timestamps
    end
    add_index :passkeys, :external_id, unique: true
    add_index :passkeys, :public_key, unique: true
  end
end
