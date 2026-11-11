class CreateOrganizationBillPositionChanges < ActiveRecord::Migration[8.0]
    def change
        create_table :organization_bill_position_changes do |t|
            t.string :previous_support, null: false
            t.string :new_support, null: false
            t.text :previous_summary, null: false
            t.text :new_summary, null: false

            t.integer :status, null: false, default: :pending # 0: pending, 1: approved, 2: rejected

            t.references :organization_bill_position, null: false, foreign_key: true

            t.references :updated_by, null: false, foreign_key: { to_table: :users }
            t.references :approved_by, null: true, foreign_key: { to_table: :users }

            t.timestamps
        end
    end
end
