# frozen_string_literal: true

class CreatePipelineRunMirrorTables < ActiveRecord::Migration[8.1]
  def change
    # ── pipeline_run_bills (R6) ─────────────────────────────────────────
    create_table :pipeline_run_bills do |t|
      t.references :legislation_pipeline_run,
        null: false,
        foreign_key: { on_delete: :cascade },
        index: true
      t.string  :bill_external_id,  null: false
      t.string  :status,            null: false, default: "pending"
      t.datetime :started_at
      t.datetime :finished_at
      t.text    :error_message
      t.integer :sort_order,        null: false, default: 0

      t.timestamps
    end

    # Composite unique on (run, bill) — supports T-44-W1 (replay safety)
    add_index :pipeline_run_bills,
      [:legislation_pipeline_run_id, :bill_external_id],
      unique: true,
      name:   "index_prb_on_run_and_bill_external_id"

    # Cross-run lookup (per SPEC R6 — supports per-bill history queries downstream)
    add_index :pipeline_run_bills, :bill_external_id

    # ── pipeline_run_stages (R6) ────────────────────────────────────────
    create_table :pipeline_run_stages do |t|
      t.references :legislation_pipeline_run,
        null: false,
        foreign_key: { on_delete: :cascade },
        index: true
      t.string  :stage_name,    null: false
      t.string  :status,        null: false, default: "pending"
      t.datetime :started_at
      t.datetime :finished_at
      t.text    :error_message

      # Pitfall #4 (D-22): text columns + serialize coder: JSON in model.
      # Defaults set as column defaults, NEVER in the serialize call.
      # SQLite stores JSON arrays as text; ActiveRecord does not auto-deserialize.
      # Matches BillLlmProvisioning.draft_org_positions serialization (Pitfall #4).
      t.text :output_summary                                # nullable
      t.text :completed_bill_external_ids, null: false, default: "[]"
      t.text :remaining_bill_external_ids, null: false, default: "[]"

      t.timestamps
    end

    # Composite unique on (run, stage_name) — supports T-44-W1 (replay safety)
    add_index :pipeline_run_stages,
      [:legislation_pipeline_run_id, :stage_name],
      unique: true,
      name:   "index_prs_on_run_and_stage_name"
  end
end
