# frozen_string_literal: true

class AddIngestColumnsToPipelineRunSummaryBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :pipeline_run_summary_batches, :ingested_at, :datetime
    add_column :pipeline_run_summary_batches, :attempt, :integer, null: false, default: 1
    add_column :pipeline_run_summary_batches, :item_count, :integer, null: false, default: 0
    add_column :pipeline_run_summary_batches, :succeeded_count, :integer, null: false, default: 0
    add_column :pipeline_run_summary_batches, :errored_count, :integer, null: false, default: 0
    add_column :pipeline_run_summary_batches, :canceled_count, :integer, null: false, default: 0
    add_column :pipeline_run_summary_batches, :expired_count, :integer, null: false, default: 0

    add_index :pipeline_run_summary_batches, :ingested_at, where: "ingested_at IS NULL"
  end
end
