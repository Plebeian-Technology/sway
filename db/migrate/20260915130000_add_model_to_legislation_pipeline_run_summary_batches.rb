# frozen_string_literal: true

# @lat: [[llm-summaries#Batch summarisation#Retaining the model for batch retries]]
class AddModelToLegislationPipelineRunSummaryBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :legislation_pipeline_run_summary_batches, :model, :string, null: true
  end
end
