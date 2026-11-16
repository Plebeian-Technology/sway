# frozen_string_literal: true

class MoveRetiredRegistrationStatesToPending < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE users
      SET registration_status = 'pending'
      WHERE registration_status IN ('processing', 'failed')
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
