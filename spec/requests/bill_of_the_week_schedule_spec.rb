require "rails_helper"

RSpec.describe "BillOfTheWeekSchedules", type: :request, inertia: true do
  include_context "SessionDouble"
  include_context "Setup"

  def get_params(sway_locale, partial_bill: {}, partial_sponsor: {}, partial_vote: {})
    legislator = create(:legislator)
    create(:bill, legislator:, sway_locale:, summary: "Tacos are great")
  end

  describe "PUT /update" do
    it "sets the bill's scheduled release date" do
      sway_locale = setup
      bill = get_params(sway_locale)

      put "/bill_of_the_week_schedule/update", params: {
        bill_of_the_week_schedule: {
          bill_id: bill.id,
          tab_key: nil,
          scheduled_release_date_utc: Time.zone.today.to_s
        }
      }

      get JSON.parse(response.body)["route"]

      expect(inertia).to render_component Pages::BILL_CREATOR
      expect(inertia).to include_props({
        bill: {
          **bill.to_sway_json,
          scheduledReleaseDateUtc: Time.zone.today,
          organizations: []
        }
      })
    end
  end
end
