class AddResumeMetadataToLegislationPipelineRuns < ActiveRecord::Migration[8.1]
  # Phase 47 D-08, D-10: parent linkage + origin discriminator.
  # parent_run_id is nullable — fresh runs have no parent.
  # origin defaults to "fresh"; resume / restart writers set explicitly.
  def change
    add_column :legislation_pipeline_runs, :parent_run_id, :string
    add_column :legislation_pipeline_runs, :origin, :string, null: false, default: "fresh"
    add_index  :legislation_pipeline_runs, :parent_run_id
  end
end
