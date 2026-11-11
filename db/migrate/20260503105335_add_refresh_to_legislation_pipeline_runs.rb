# frozen_string_literal: true

# @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart]]
class AddRefreshToLegislationPipelineRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :legislation_pipeline_runs, :refresh, :boolean, null: false, default: true
  end
end
