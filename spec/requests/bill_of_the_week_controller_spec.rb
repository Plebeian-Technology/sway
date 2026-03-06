require "rails_helper"

RSpec.describe "BillOfTheWeek", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:build_bill_of_the_week) do
    lambda do |sway_locale|
      legislator = create(:legislator)
      create(
        :bill,
        legislator:,
        sway_locale:,
        summary: "Tacos are great",
        scheduled_release_date_utc: Time.zone.now,
      )
    end
  end

  describe "GET /index" do
    it "gets the bill of the week" do
      sway_locale, _user = setup
      bill = build_bill_of_the_week.call(sway_locale)

      get "/bill_of_the_week"

      expect(inertia).to render_component Pages::BILL_OF_THE_WEEK
      expect(inertia.props[:bill]["id"]).to eql(bill.id)
    end
  end
end
