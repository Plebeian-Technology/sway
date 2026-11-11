# frozen_string_literal: true

require "rails_helper"
require "support/query_plan_helpers"

RSpec.describe "Activity log query plans" do
  it "reads the composite index for the errors-only filter" do
    statements = select_statements_matching(/FROM "pipeline_activity_log_entries"/) do
      BillCreator::ActivityLogPage.call(
        bill: nil,
        subject: "all_bills",
        severity: "errors",
        window: "all",
        cursor: nil
      )
    end

    expect(statements.size).to eq(1)

    details = query_plan_details(statements.first)

    expect(details).to include(
      a_string_including("SEARCH pipeline_activity_log_entries USING INDEX index_activity_log_severity_and_created_at")
    )
    expect(details).not_to include(a_string_including("USE TEMP B-TREE FOR ORDER BY"))
  end
end
