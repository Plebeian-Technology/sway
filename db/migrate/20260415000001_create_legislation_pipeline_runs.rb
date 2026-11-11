# frozen_string_literal: true

class CreateLegislationPipelineRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :legislation_pipeline_runs do |t|
      # Nullable FK: global runs have bill_id NULL; per-bill refresh has bill_id set.
      t.references :bill, null: true, foreign_key: true, index: false

      # Remote run ID from the FastAPI control plane (UUID/string).
      t.string :remote_run_id

      # State machine column. Initial value is "queued" (NOT nil — unlike
      # BillLlmProvisioning.generation_status, every LegislationPipelineRun
      # row represents an active or historical run).
      t.string :status, null: false, default: "queued"

      # Progress reporting.
      t.string :current_stage
      t.text :error_message

      # Run metadata.
      t.integer :bill_count
      t.string :bill_filter

      # JSON-serialized array of stage keys (e.g. ["fetch-bills", "extract-text"]).
      # SQLite stores this as TEXT; ActiveRecord `serialize :stages, coder: JSON`
      # handles (de)serialization. Do NOT use t.json — Phase 18 pitfall #4.
      t.text :stages

      # Timing.
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    # Global active-run guard: enforces at most one running/queued global
    # pipeline run at a time. Per-bill runs are allowed concurrently with
    # the global guard because bill_id is NOT NULL for them.
    add_index :legislation_pipeline_runs, :bill_id
    add_index :legislation_pipeline_runs, :status
    add_index :legislation_pipeline_runs, :remote_run_id, unique: true, where: "remote_run_id IS NOT NULL"
  end
end
