class AddStatusToUserOrganizationMemberships < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationUserOrganizationMembership < ActiveRecord::Base
    self.table_name = "user_organization_memberships"
  end

  def up
    add_column :user_organization_memberships, :status, :string
    MigrationUserOrganizationMembership.reset_column_information
    MigrationUserOrganizationMembership.where(status: nil).update_all(status: "active")
    change_column_null :user_organization_memberships, :status, false
  end

  def down
    remove_column :user_organization_memberships, :status
  end
end
