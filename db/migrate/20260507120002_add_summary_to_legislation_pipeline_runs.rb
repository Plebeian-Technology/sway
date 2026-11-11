class AddSummaryToLegislationPipelineRuns < ActiveRecord::Migration[8.1]
  # Phase 47 D-13: terminal-event RunSummary block, JSON-serialized.
  # Phase 44 D-22 pattern: text column + serialize coder: JSON in model.
  # Nullable: empty until terminal webhook arrives (D-12).
  def change
    add_column :legislation_pipeline_runs, :summary, :text
  end
end
