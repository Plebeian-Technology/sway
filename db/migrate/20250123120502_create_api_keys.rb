# https://keygen.sh/blog/how-to-implement-api-key-authentication-in-rails-without-devise/
class CreateApiKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :api_keys do |t|
      t.integer :bearer_id, null: false
      t.string :bearer_type, null: false
      t.string :token_digest, null: false
      t.string :name, null: true
      t.datetime :last_used_on_utc, null: true
      t.timestamps null: false
    end

    add_index :api_keys, [:bearer_id, :bearer_type]
    add_index :api_keys, :token_digest, unique: true
  end
end
