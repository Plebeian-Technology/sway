# frozen_string_literal: true

# @lat: [[bill-status-normalisation#The allowlist is checked on the way in, not on the way past]]
# @lat: [[bill-external-id-normalisation#Why the check is conditional]]
class RepairBills58And59 < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  # A stand-in model avoids referencing the application Bill model, which would
  # fail MigrationModelCheck (rake sway:lint:migration_models).
  #
  # Because a stand-in skips model callbacks, normalize_external_id does not run;
  # therefore external_id is explicitly stripped of leading whitespace here.
  #
  # Status values were read from Baltimore Legistar API on 2026-09-09:
  # - Matter 9906 (24-0599, Bill 58): MatterStatusName "Failed - End of Term" maps to "failed"
  # - Matter 9895 (24-0592, Bill 59): MatterStatusName "Enacted" maps to "passed"
  class MigrationSwayLocale < ActiveRecord::Base
    self.table_name = "sway_locales"
  end

  class MigrationBill < ActiveRecord::Base
    self.table_name = "bills"
  end

  REPAIRS = [
    {
      target_id: 58,
      file_number: "24-0599",
      status: "failed",
      matter_id: 9906,
      upstream_status: "Failed - End of Term"
    },
    {
      target_id: 59,
      file_number: "24-0592",
      status: "passed",
      matter_id: 9895,
      upstream_status: "Enacted"
    }
  ].freeze

  def up
    MigrationSwayLocale.reset_column_information
    MigrationBill.reset_column_information

    baltimore_locale_ids = MigrationSwayLocale.where("LOWER(city) = ?", "baltimore").pluck(:id)
    return if baltimore_locale_ids.empty?

    scoped_bills = MigrationBill.where(sway_locale_id: baltimore_locale_ids)

    REPAIRS.each do |repair|
      bills = scoped_bills
        .where(id: repair[:target_id])
        .or(scoped_bills.where("external_id LIKE ?", "%#{repair[:file_number]}"))
        .select { |bill| bill.external_id.to_s.strip == repair[:file_number] }

      bills.each do |bill|
        bill.update_columns(
          external_id: bill.external_id.to_s.strip,
          status: repair[:status]
        )
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
