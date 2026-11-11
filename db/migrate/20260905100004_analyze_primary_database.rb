# frozen_string_literal: true

# @lat: [[query-plan-indexes#Statistics the planner reads]]
class AnalyzePrimaryDatabase < ActiveRecord::Migration[8.1]
  # Rows sampled per index; SQLite's `analysis_limit` pragma.
  ANALYSIS_LIMIT = 400

  def up
    connection.execute("PRAGMA analysis_limit=#{ANALYSIS_LIMIT}")
    connection.execute("ANALYZE")
  end

  def down
    connection.execute("DELETE FROM sqlite_stat1")
  end
end
