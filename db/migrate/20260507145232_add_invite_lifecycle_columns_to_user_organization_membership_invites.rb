class AddInviteLifecycleColumnsToUserOrganizationMembershipInvites < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationInvite < ActiveRecord::Base
    self.table_name = "user_organization_membership_invites"
  end

  def up
    add_column :user_organization_membership_invites, :accepted_at, :datetime
    add_column :user_organization_membership_invites, :expires_at, :datetime
    add_column :user_organization_membership_invites, :revoked_at, :datetime
    add_reference :user_organization_membership_invites, :invitee_user,
      foreign_key: { to_table: :users }, null: true

    # Backfill expires_at for existing rows: created_at + 14 days
    MigrationInvite.reset_column_information
    MigrationInvite.where(expires_at: nil).find_each do |invite|
      invite.update_columns(expires_at: invite.created_at + 14.days)
    end

    add_index :user_organization_membership_invites, :expires_at
    add_index :user_organization_membership_invites, :accepted_at
    add_index :user_organization_membership_invites, :revoked_at
  end

  def down
    remove_index  :user_organization_membership_invites, :expires_at
    remove_index  :user_organization_membership_invites, :accepted_at
    remove_index  :user_organization_membership_invites, :revoked_at
    remove_reference :user_organization_membership_invites, :invitee_user,
      foreign_key: { to_table: :users }
    remove_column :user_organization_membership_invites, :revoked_at
    remove_column :user_organization_membership_invites, :expires_at
    remove_column :user_organization_membership_invites, :accepted_at
  end
end
