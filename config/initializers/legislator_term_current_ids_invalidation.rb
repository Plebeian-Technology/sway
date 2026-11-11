# frozen_string_literal: true

# @lat: [[current-legislator-term#Why the memo is dropped by watching statements, not callbacks]]
ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
  sql = payload[:sql]
  if sql.is_a?(String) && sql.include?("legislator_terms") &&
      sql.match?(/\A\s*(INSERT|UPDATE|DELETE|REPLACE)\b/i)
    LegislatorTerm.forget_current_ids
  end
end
