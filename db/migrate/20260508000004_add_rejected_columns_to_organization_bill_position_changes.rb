# frozen_string_literal: true

# Phase 999.2 D-02 — soft-reject for OrganizationBillPositionChange.
# Mirrors the approved_by_id / approved_at semantics. The :rejected enum
# value (=2) already exists on the model; this migration only adds the
# audit columns (rejected_by + rejected_at) so the controller can record
# who soft-rejected the change and when.
#
# IN-02 (iter1 review): type: :integer is symmetric with the existing
# approved_by_id column on this table (db/schema.rb table uses t.integer
# for id columns). On SQLite this is a no-op (INTEGER == INTEGER). If the
# project ever migrates to Postgres with the modern :bigint default, the
# entire table will need a coordinated id-type sweep — that is a
# project-wide decision, not phase-local. Filed as a follow-up note.
class AddRejectedColumnsToOrganizationBillPositionChanges < ActiveRecord::Migration[8.1]
  def change
    add_reference :organization_bill_position_changes,
                  :rejected_by,
                  type: :integer,
                  null: true,
                  foreign_key: { to_table: :users },
                  index: true

    add_column :organization_bill_position_changes,
               :rejected_at,
               :datetime,
               null: true
  end
end
