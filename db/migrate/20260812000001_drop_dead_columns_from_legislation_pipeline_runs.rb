# frozen_string_literal: true

# @lat: [[migrations-name-no-model#Migrations name no model#A column nothing writes is dropped in its own change]]
class DropDeadColumnsFromLegislationPipelineRuns < ActiveRecord::Migration[8.1]
  def change
    remove_column :legislation_pipeline_runs, :bill_count, :integer
    remove_column :legislation_pipeline_runs, :summary, :text
  end
end
