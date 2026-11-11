# frozen_string_literal: true

# @lat: [[organization-position-removal#Taking an organization's position off a bill#A draft with no testimony behind it is not approvable]]
class RetireUntestifiedDraftOrgPositions < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationBillLlmProvisioning < ActiveRecord::Base
    self.table_name = "bill_llm_provisionings"

    # The column is text holding JSON, which is how the model reads it too.
    serialize :draft_org_positions, coder: JSON

    def testimony_present?
      extracted_testimony.present? || supplemental_testimony.present?
    end
  end

  # The predicate, as a relation, directly assertable against the issue's
  # acceptance criterion (which rows) — the Ruby-side guards in #up produce
  # the same outcome whether or not the SQL half works.
  #
  # @lat: [[draft-org-position-identity#Querying for a non-empty draft_org_positions]]
  #
  # Answers ONE of two questions — does the row hold drafts. See
  # .untestified_draft_rows for the testimony question.
  def self.draft_bearing_rows
    MigrationBillLlmProvisioning
      .where.not(draft_org_positions: nil)
      .where(MigrationBillLlmProvisioning.arel_table[:draft_org_positions].not_eq([]))
  end

  # THE PREDICATE, still directly assertable against the issue's acceptance
  # criterion — the Ruby-side guards in #up produce the same outcome whether
  # or not the row set is right.
  #
  # Uses the stand-in's testimony_present?, not a SQL comparison on
  # extracted_testimony/supplemental_testimony.
  #
  # @lat: [[draft-org-position-identity#Querying for a non-empty draft_org_positions]]
  #
  # Materialises #draft_bearing_rows. Does not reach a row with real
  # supplemental_testimony — see the class doc above.
  #
  # @return [Array<BillLlmProvisioning>]
  def self.untestified_draft_rows
    draft_bearing_rows.reject(&:testimony_present?)
  end

  def up
    stamped_rows = 0
    stamped_drafts = 0

    self.class.untestified_draft_rows
      .each do |provisioning|
        raw = provisioning.draft_org_positions
        next if raw.blank?

        drafts = raw.is_a?(::Array) ? raw : []
        next if drafts.empty?

        # Idempotent: an already-stamped entry keeps its original timestamp, so
        # a re-run is a no-op and the count below reports only new marks.
        newly = drafts.count { |entry| entry.is_a?(::Hash) && !BillLlmProvisioning.draft_evidence_retracted?(entry) }
        next if newly.zero?

        provisioning.update_columns(
          draft_org_positions: BillLlmProvisioning.drafts_with_evidence_retracted(drafts)
        )
        stamped_rows += 1
        stamped_drafts += newly
      end

    say "stamped #{stamped_drafts} draft org position(s) across #{stamped_rows} bill(s) as evidence-retracted (no testimony backing)"
  end

  # Clearing the mark wholesale would also clear marks half (a) wrote for a
  # genuine retraction, which this migration did not create and must not
  # destroy. The forward direction is already non-destructive and the ordinary
  # operator workflow (regenerate, or reject the draft) undoes it per bill.
  def down
    raise ActiveRecord::IrreversibleMigration,
      "marks are indistinguishable from FetchHearingsService's own retraction stamps; " \
      "regenerate positions on a bill to clear its mark"
  end
end
