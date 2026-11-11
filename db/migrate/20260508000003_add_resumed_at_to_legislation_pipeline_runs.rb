# frozen_string_literal: true

# Phase 48 D-02 (BL-02 fix): timestamp of most-recent run resume.
# Set by the run_resumed webhook receiver (Plan 04). Mirrors the FastAPI-side
# resume hook in lifespan + /resume endpoint (Phase 47 D-06). NULL for runs
# that have never been resumed; non-NULL after a resume webhook lands.
class AddResumedAtToLegislationPipelineRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :legislation_pipeline_runs, :resumed_at, :datetime
  end
end
