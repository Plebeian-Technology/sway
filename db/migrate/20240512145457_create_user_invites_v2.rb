class CreateUserInvitesV2 < ActiveRecord::Migration[7.1]
  def change
    create_table :user_invites do |t|
      t.references :user, null: false, foreign_key: true
      t.string :invite_uuid, null: false

      t.timestamps
    end

    add_index :user_invites, :invite_uuid, unique: true
  end
end
