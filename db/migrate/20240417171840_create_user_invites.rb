# typed: true
class CreateUserInvites < ActiveRecord::Migration[7.1]
  def change
    create_table :user_invites do |t|
      t.references :user, null: false, foreign_key: true
      t.string :invitee_email
      t.datetime :invite_expires_on_utc
      t.datetime :invite_accepted_on_utc

      t.timestamps
    end
  end
end
