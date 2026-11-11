class CreateRefreshTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :refresh_tokens do |t|
      t.belongs_to :user, null: false, foreign_key: true
      t.datetime :expires_at, null: false
      t.string :token, null: false
      t.string :ip_address, null: false
      t.string :user_agent, null: false

      t.timestamps
    end

    add_index :refresh_tokens, :token, unique: true
  end
end
