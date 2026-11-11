# frozen_string_literal: true

# @lat: [[query-plan-indexes#The activity log's errors-only filter]]
class ReplaceActivityLogSeverityIndex < ActiveRecord::Migration[8.1]
  def up
    add_index :pipeline_activity_log_entries,
      [:severity, :created_at],
      order: {created_at: :desc},
      name: "index_activity_log_severity_and_created_at"

    remove_index :pipeline_activity_log_entries,
      name: "index_pipeline_activity_log_entries_on_severity"
  end

  def down
    add_index :pipeline_activity_log_entries,
      :severity,
      name: "index_pipeline_activity_log_entries_on_severity"

    remove_index :pipeline_activity_log_entries,
      name: "index_activity_log_severity_and_created_at"
  end
end
