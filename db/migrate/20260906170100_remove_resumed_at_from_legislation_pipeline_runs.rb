# frozen_string_literal: true

class RemoveResumedAtFromLegislationPipelineRuns < ActiveRecord::Migration[8.1]
  def change
    remove_column :legislation_pipeline_runs, :resumed_at, :datetime
  end
end
