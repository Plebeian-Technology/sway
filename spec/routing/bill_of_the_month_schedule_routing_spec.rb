# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-of-the-month-schedule-admin-guard-order#Why the GET route to update is pinned as removed]]
RSpec.describe "BillOfTheMonthSchedule routing", type: :routing do
  it "does not route GET /bill_of_the_month_schedule/update to the mutating action" do
    expect(get: "/bill_of_the_month_schedule/update").not_to be_routable
  end

  it "does not route GET /bill_of_the_month_schedule/:id" do
    expect(get: "/bill_of_the_month_schedule/1").not_to be_routable
  end

  it "routes PUT /bill_of_the_month_schedule/:id to #update" do
    expect(put: "/bill_of_the_month_schedule/1").to route_to(
      controller: "bill_of_the_month_schedule",
      action: "update",
      id: "1"
    )
  end

  it "routes api admin PUT /api/admin/bill_of_the_month_schedule/:id to #update" do
    expect(put: "/api/admin/bill_of_the_month_schedule/1").to route_to(
      controller: "bill_of_the_month_schedule",
      action: "update",
      id: "1"
    )
  end
end
