class CreateInvites < ActiveRecord::Migration[7.1]
  def change
    create_table :invites do |t|
      t.references :inviter, null: false, foreign_key: { to_table: :users }
      t.references :invitee, null: true, foreign_key: { to_table: :users }
      t.string :invitee_phone, null: false
      t.datetime :invite_accepted_on_utc

      t.timestamps
    end

    add_index :invites, [:invitee_phone], unique: true
  end
end
