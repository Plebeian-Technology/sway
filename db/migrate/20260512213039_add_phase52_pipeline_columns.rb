# frozen_string_literal: true

# Phase 52 Plan 01 Task 4 (review issues 2 + 4): add the columns Plans
# 04/05/06/07/09 reference but db/schema.rb did not yet have. SCHEMA-AUDIT.md
# in the phase directory is the authoritative cross-reference.
#
# Columns added:
#   * bills.extracted_text                — Plan 02/05/07 (PDF extraction)
#   * bills.parsed_sections               — Plan 05/07 (section parse output)
#   * bills.previous_parsed_sections      — Plan 05 diff "before" snapshot
#   * pipeline_run_bills.stage_results    — Plan 07 per-stage success tracking
#                                           (review issue 2; required for the
#                                           per-bill success contract)
#
# Idempotent via column_exists? guards so partial pre-existing state on any
# environment doesn't break the migration (and a re-run on a freshly
# bootstrapped DB is a no-op for already-applied deltas).
#
# NOT added: legislation_pipeline_runs.origin — already present per
# 20260507120001_add_resume_metadata_to_legislation_pipeline_runs.rb.
class AddPhase52PipelineColumns < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:pipeline_run_bills, :stage_results)
      add_column :pipeline_run_bills, :stage_results, :json, default: {}, null: false
    end

    unless column_exists?(:bills, :extracted_text)
      add_column :bills, :extracted_text, :text
    end

    unless column_exists?(:bills, :parsed_sections)
      add_column :bills, :parsed_sections, :json
    end

    unless column_exists?(:bills, :previous_parsed_sections)
      add_column :bills, :previous_parsed_sections, :json
    end
  end
end
