class DropUserInvitesTable < ActiveRecord::Migration[7.1]
  def change
    drop_table :user_invites
  end
end
