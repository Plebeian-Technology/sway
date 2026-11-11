# frozen_string_literal: true

class AddSummaryBatchColumnsToLegislationPipelineRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :legislation_pipeline_runs, :summary_batch_id, :string
    add_column :legislation_pipeline_runs, :summary_batch_submitted_at, :datetime
    add_column :legislation_pipeline_runs, :summary_batch_expires_at, :datetime

    add_index :legislation_pipeline_runs, :summary_batch_id, unique: true, where: "summary_batch_id IS NOT NULL"
  end
end
