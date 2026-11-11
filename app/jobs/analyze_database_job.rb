# frozen_string_literal: true

# @lat: [[query-plan-indexes#Statistics the planner reads]]
class AnalyzeDatabaseJob < ApplicationJob
  queue_as :background

  ANALYSIS_LIMIT = 400

  def perform
    connection = ActiveRecord::Base.connection
    connection.execute("PRAGMA analysis_limit=#{ANALYSIS_LIMIT}")
    connection.execute("ANALYZE")

    rows = connection.select_value("SELECT COUNT(*) FROM sqlite_stat1").to_i
    SwayLogging.info("[AnalyzeDatabaseJob] complete sqlite_stat1_rows=#{rows} analysis_limit=#{ANALYSIS_LIMIT}")
    rows
  end
end
