# frozen_string_literal: true

# Phase 52 Plan 05 Task 1 — bill_amendment_operations table (D-46).
#
# One row per text-pattern regex hit found in bill.extracted_text. Created
# by ParseSectionsService. Attributed to nearest preceding BillSectionReference
# (parse_sections.py:513-526 section attribution).
#
# operation enum (D-46): {strike: 0, insert: 1, replace: 2}
# source    enum (D-46): {text_pattern: 0, markup: 1} — Phase 52 emits text_pattern only (D-42)
class CreateBillAmendmentOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :bill_amendment_operations do |t|
      t.references :bill, null: false, foreign_key: true, index: true
      t.references :bill_section_reference, null: true, foreign_key: true, index: true
      t.references :target_law_section, null: true,
        foreign_key: { to_table: :law_sections }, index: true
      t.integer :operation, null: false             # D-46 {strike: 0, insert: 1, replace: 2}
      t.integer :source, null: false, default: 0   # D-46 {text_pattern: 0, markup: 1}
      t.text :anchor_text                          # STRIKE / REPLACE — raw matched text
      t.text :replacement_text                     # INSERT — matched phrase (text_pattern source)
      t.integer :char_start, null: false, default: -1
      t.integer :char_end, null: false, default: -1
      t.integer :ordinal, null: false
      t.timestamps
    end
    add_index :bill_amendment_operations, [:bill_id, :ordinal],
      name: "idx_bill_amendment_ops_on_bill_ordinal"
  end
end
