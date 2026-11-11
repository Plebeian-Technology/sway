# frozen_string_literal: true

class AddIdempotencyKeyToLegislationPipelineRuns < ActiveRecord::Migration[8.1]
  # WR-06: stub class scoped to the migration so this migration is insulated
  # from future LegislationPipelineRun model evolution (renames, validations
  # that fail on legacy rows, default scopes, callback changes). Follows the
  # standard Rails migration pattern.
  class StubRun < ActiveRecord::Base
    self.table_name = "legislation_pipeline_runs"
  end

  def up
    add_column :legislation_pipeline_runs, :idempotency_key, :string

    StubRun.reset_column_information
    # Guard against re-runs (e.g., db:rollback then db:migrate against rows
    # that already got a key from a prior partial run): only backfill where
    # the column is still nil.
    StubRun.where(idempotency_key: nil).find_each do |run|
      run.update_columns(idempotency_key: SecureRandom.uuid)
    end

    change_column_null :legislation_pipeline_runs, :idempotency_key, false
    add_index :legislation_pipeline_runs, :idempotency_key, unique: true
  end

  def down
    remove_index  :legislation_pipeline_runs, :idempotency_key
    remove_column :legislation_pipeline_runs, :idempotency_key
  end
end
