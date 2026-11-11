# frozen_string_literal: true

# Phase 52 Plan 05 Task 1 — Q6 ParsedBill mapping columns on bills.
#
# RESEARCH-REPLAN §Q6: Python's ParsedBill JSON shape is reconstructed at
# rake/serialize time from these columns + bill_section_references rows +
# bill_amendment_operations rows. NO jsonb blob on bills.
#
# D-50: bills.parsed_sections jsonb (added by Plan 01) is left in place
# (unwritten) through Phase 52 and dropped post-release. Do NOT touch it.
#
# Idempotent column_exists? guards (matches the Plan 01 add_phase52
# precedent) so partial pre-existing state cannot break the migration.
class AddPhase52ParsedBillColumnsToBills < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:bills, :amendment_source)
      add_column :bills, :amendment_source, :string # "text_pattern" | "markup" | "none"
    end
    unless column_exists?(:bills, :parsing_target)
      add_column :bills, :parsing_target, :string # "charter" | "code"
    end
    unless column_exists?(:bills, :parsing_target_log)
      add_column :bills, :parsing_target_log, :string # free-form classifier text (forensic)
    end
    unless column_exists?(:bills, :parsed_at)
      add_column :bills, :parsed_at, :datetime
    end

    unless index_exists?(:bills, :parsing_target, name: "idx_bills_on_parsing_target")
      add_index :bills, :parsing_target, name: "idx_bills_on_parsing_target"
    end
    unless index_exists?(:bills, :amendment_source, name: "idx_bills_on_amendment_source")
      add_index :bills, :amendment_source, name: "idx_bills_on_amendment_source"
    end
  end
end
