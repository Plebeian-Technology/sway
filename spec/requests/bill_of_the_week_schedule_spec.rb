require "rails_helper"

RSpec.describe "BillOfTheWeekSchedules", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:build_bill_for_schedule) do
    lambda do |sway_locale|
      legislator = create(:legislator)
      create(:bill, legislator:, sway_locale:, summary: "Tacos are great")
    end
  end

  describe "PUT /update" do
    it "sets the bill's scheduled release date" do
      sway_locale, _user = setup
      bill = build_bill_for_schedule.call(sway_locale)

      put "/bill_of_the_week_schedule/update",
          params: {
            bill_of_the_week_schedule: {
              bill_id: bill.id,
              tab_key: nil,
              scheduled_release_date_utc: Time.zone.today.to_s,
            },
          }

      get JSON.parse(response.body)["route"]

      expect(inertia).to render_component Pages::BILL_CREATOR
      empty_organizations = []
      # @type var empty_organizations: Array[untyped]
      expect(inertia.props[:bill].deep_symbolize_keys).to eql(
        {
          **bill.to_sway_json,
          scheduled_release_date_utc: Time.zone.today,
          organizations: empty_organizations,
        }.deep_symbolize_keys,
      )
    end
  end
end
