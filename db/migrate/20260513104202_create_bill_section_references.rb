# frozen_string_literal: true

# Phase 52 Plan 05 Task 1 — bill_section_references table (D-47).
#
# One row per detected `§ART__SEC` citation in bill.extracted_text. Created
# by ParseSectionsService.
#
# resolution enum (D-47):
#   0 exact      — bill cite matched a LawSection.key in the bill's locale
#   1 fuzzy      — Wagner-Fischer/Levenshtein ratio above threshold matched
#   2 unresolved — no match (key recorded for forensics)
class CreateBillSectionReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :bill_section_references do |t|
      t.references :bill, null: false, foreign_key: true, index: true
      t.string :key, null: false
      t.string :article, null: false
      t.string :section, null: false
      t.string :title
      t.text :anchor # literal text in the bill referencing this section (forensic)
      t.integer :resolution, null: false, default: 2 # D-47 — default :unresolved
      t.integer :fuzzy_score # null unless resolution == :fuzzy
      t.integer :ordinal, null: false # insertion order within the bill
      t.timestamps
    end
    add_index :bill_section_references, [:bill_id, :ordinal],
      name: "idx_bill_section_refs_on_bill_ordinal"
    add_index :bill_section_references, :key,
      name: "idx_bill_section_refs_on_key"
  end
end
