# frozen_string_literal: true

class CreatePipelineRunSummaryBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :pipeline_run_summary_batches do |t|
      t.references :legislation_pipeline_run,
        null: false,
        foreign_key: {on_delete: :cascade},
        index: {name: "index_pipeline_run_summary_batches_on_run_id"}
      t.string :batch_id, null: false
      t.datetime :submitted_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :pipeline_run_summary_batches, :batch_id, unique: true

    remove_index :legislation_pipeline_runs, :summary_batch_id,
      unique: true, where: "summary_batch_id IS NOT NULL"
    remove_column :legislation_pipeline_runs, :summary_batch_id, :string
    remove_column :legislation_pipeline_runs, :summary_batch_submitted_at, :datetime
    remove_column :legislation_pipeline_runs, :summary_batch_expires_at, :datetime
  end
end
