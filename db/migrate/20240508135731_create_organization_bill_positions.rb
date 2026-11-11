class CreateOrganizationBillPositions < ActiveRecord::Migration[7.1]
  def change
    create_table :organization_bill_positions do |t|
      t.references :bill, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :support, null: false
      t.text :summary, null: false

      t.timestamps
    end

    add_index :organization_bill_positions, [:bill_id, :organization_id], unique: true
  end
end
