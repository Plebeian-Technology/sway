# frozen_string_literal: true

class AddActivatedAtToOrganizationBillPositions < ActiveRecord::Migration[8.1]
  def change
    add_column :organization_bill_positions, :activated_at, :datetime
  end
end
