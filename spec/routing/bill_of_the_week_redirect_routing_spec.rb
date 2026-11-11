# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-of-the-month-schedule-admin-guard-order#Envelope parameter extraction]]
RSpec.describe "Retired Bill of the Week routes", type: :routing do
  it "does not route PUT /bill_of_the_week_schedule/:id" do
    expect(put: "/bill_of_the_week_schedule/1").not_to be_routable
  end

  it "does not route PUT /api/admin/bill_of_the_week_schedule/:id" do
    expect(put: "/api/admin/bill_of_the_week_schedule/1").not_to be_routable
  end
end
