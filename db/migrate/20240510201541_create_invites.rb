class CreateInvites < ActiveRecord::Migration[7.1]
  def change
    create_table :invites do |t|
      t.references :inviter, null: false, foreign_key: { to_table: :users }
      t.references :invitee, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :invites, [:inviter_id, :inviter_id], unique: true
  end
end
