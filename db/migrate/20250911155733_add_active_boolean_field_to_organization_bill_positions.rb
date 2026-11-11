class AddActiveBooleanFieldToOrganizationBillPositions < ActiveRecord::Migration[8.0]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationOrganizationBillPosition < ActiveRecord::Base
    self.table_name = "organization_bill_positions"
  end

  def change
    add_column :organization_bill_positions, :active, :boolean, default: false, null: false
    add_index :organization_bill_positions, :active

    MigrationOrganizationBillPosition.reset_column_information
    MigrationOrganizationBillPosition.update_all(active: true)
  end
end
