# frozen_string_literal: true

require "rails_helper"
require "support/query_plan_helpers"

# @lat: [[query-plan-indexes#Bill of the month reads by locale then date]]
RSpec.describe "Bill of the month query plans" do
  let(:sway_locale) { create(:sway_locale) }

  it "reads an index for both queries and never sorts through a temporary b-tree" do
    statements = select_statements_matching(/FROM "bills"/) do
      Bill.of_the_month(sway_locale: sway_locale)
    end

    expect(statements.size).to eq(2)

    statements.each do |sql|
      details = query_plan_details(sql)

      expect(details).to include(a_string_including("SEARCH"))
      expect(details).not_to include(a_string_including("USE TEMP B-TREE FOR ORDER BY"))
    end
  end
end
