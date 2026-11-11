# frozen_string_literal: true

# @lat: [[query-plan-indexes#Index shapes the query planner can use]]
module QueryPlanHelpers
  def query_plan_details(query)
    sql = query.respond_to?(:to_sql) ? query.to_sql : query.to_s

    ActiveRecord::Base.connection
      .select_all("EXPLAIN QUERY PLAN #{sql}")
      .map { |row| row["detail"].to_s }
  end

  def select_statements_matching(pattern)
    statements = []

    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      statements << sql if sql.start_with?("SELECT") && pattern.match?(sql)
    end

    begin
      yield

      statements
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end
  end
end

RSpec.configure do |config|
  config.include QueryPlanHelpers
end
