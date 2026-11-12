# frozen_string_literal: true

class BackfillOrganizationBillPositionActivatedAt < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE organization_bill_positions
      SET activated_at = updated_at
      WHERE active = TRUE
        AND activated_at IS NULL
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
