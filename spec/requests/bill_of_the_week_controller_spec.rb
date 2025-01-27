require "rails_helper"

RSpec.describe "BillOfTheWeek", type: :request, inertia: true do
  include_context "SessionDouble"
  include_context "Setup"

  def get_params(sway_locale, partial_bill: {}, partial_sponsor: {}, partial_vote: {})
    legislator = create(:legislator)
    create(:bill, legislator:, sway_locale:, summary: "Tacos are great", scheduled_release_date_utc: Time.zone.today)
  end

  describe "GET /index" do
    it "gets the bill of the week" do
      sway_locale, _user = setup
      bill = get_params(sway_locale)

      get "/bill_of_the_week"

      expect(inertia).to render_component Pages::BILL_OF_THE_WEEK
      expect(inertia).to include_props({
        bill: bill.to_sway_json
      })
    end
  end
end
