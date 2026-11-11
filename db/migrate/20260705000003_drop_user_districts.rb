# frozen_string_literal: true

# WS2.5 — the user_districts table has no production write path. Nothing in app/
# or lib/ ever created a UserDistrict row; the only writer was the dev seed
# graph, and SwayRegistrationService assigns UserLegislators only. The two SMS
# recipient queries that read it were rewritten to derive locale membership live
# from active user_legislators (previous commit), so the table is now dead.
#
# The drop_table block mirrors the original CreateUserDistricts migration so the
# migration is fully reversible (db:rollback recreates the table).
class DropUserDistricts < ActiveRecord::Migration[8.1]
  def change
    drop_table :user_districts do |t|
      t.references :district, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
