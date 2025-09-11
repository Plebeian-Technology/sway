class AddActiveBooleanFieldToOrganizationBillPositions < ActiveRecord::Migration[8.0]
  def change
    add_column :organization_bill_positions, :active, :boolean, default: false, null: false
    add_index :organization_bill_positions, :active

    OrganizationBillPosition.update_all(active: true)
  end
end
