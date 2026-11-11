# frozen_string_literal: true

class RenamePipelineRunChildTables < ActiveRecord::Migration[8.1]
  def change
    rename_table :pipeline_run_bills, :legislation_pipeline_run_bills
    rename_table :pipeline_run_stages, :legislation_pipeline_run_stages
    rename_table :pipeline_run_summary_batches, :legislation_pipeline_run_summary_batches
  end
end
