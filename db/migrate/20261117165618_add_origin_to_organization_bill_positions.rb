class AddOriginToOrganizationBillPositions < ActiveRecord::Migration[8.1]
  def change
    add_column :organization_bill_positions, :origin, :string
    add_column :organization_bill_positions, :origin_url, :string
  end
end
