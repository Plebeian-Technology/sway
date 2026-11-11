# frozen_string_literal: true

# Phase 49 D-01..D-04: append-only activity log table for pipeline events.
# No updated_at (rows are immutable — model enforces via readonly?).
# payload stored as TEXT with serialize :payload, coder: JSON (D-02).
# Four indexes support the filter-chip queries defined in D-09.
class CreatePipelineActivityLogEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :pipeline_activity_log_entries do |t|
      t.string :event_type, null: false
      t.string :severity,   null: false
      t.string :title,      null: false
      t.string :message,    null: false
      t.string :subject_type, null: true
      t.string :subject_id,   null: true
      t.references :actor_user, foreign_key: { to_table: :users }, null: true
      t.text :payload, null: false, default: "{}"

      t.datetime :created_at, null: false
    end

    add_index :pipeline_activity_log_entries, :created_at,
      order: { created_at: :desc },
      name: "index_activity_log_entries_on_created_at_desc"

    add_index :pipeline_activity_log_entries, :event_type

    add_index :pipeline_activity_log_entries, [:subject_type, :subject_id],
      name: "index_activity_log_entries_on_subject_polymorphic"

    add_index :pipeline_activity_log_entries, :severity
  end
end
