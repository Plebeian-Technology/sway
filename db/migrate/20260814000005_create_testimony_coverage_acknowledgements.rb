# frozen_string_literal: true

# Phase 67 Plan 08 (D-15): one row per (bill, exact set of coverage numbers)
# an operator has said they read. AcknowledgeTestimonyCoverageService is the
# only writer; Testimony::CoverageReport is the only reader that decides
# whether a row still applies.
class CreateTestimonyCoverageAcknowledgements < ActiveRecord::Migration[8.1]
  def change
    create_table :testimony_coverage_acknowledgements do |t|
      t.references :bill, null: false, foreign_key: true, index: false

      t.references :acknowledged_by, null: false, foreign_key: {to_table: :users}

      # An acknowledgement belongs to the numbers that produced it
      # (Testimony::CoverageReport#digest, a SHA256 of the exact counts the
      # operator was shown — 67-UI-SPEC.md E6's "partial" row). Re-running the
      # clean-testimony stage changes those counts, so this stored digest no
      # longer matches the report's current one and the coverage reads as
      # unacknowledged again. Chosen deliberately over letting an
      # acknowledgement survive a re-run, so nobody can approve against
      # numbers they were never shown — at the cost of one extra click during
      # the tuning loop D-02 expects.
      t.string :coverage_digest, null: false

      # Which run produced the acknowledged numbers, when one is known.
      # Informational only — matching is entirely by coverage_digest above,
      # never by this column.
      t.references :legislation_pipeline_run, null: true, foreign_key: true

      t.timestamps
    end

    # Makes "acknowledging twice with the same numbers leaves one row" a real
    # guarantee rather than a convention AcknowledgeTestimonyCoverageService
    # merely happens to follow.
    add_index :testimony_coverage_acknowledgements,
      %i[bill_id coverage_digest],
      unique: true,
      name: "index_testimony_coverage_acks_on_bill_and_digest"
  end
end
