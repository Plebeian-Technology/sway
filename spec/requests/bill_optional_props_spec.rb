# frozen_string_literal: true

require "rails_helper"

# @lat: [[lazy-inertia-props#Lazy Inertia props]]
RSpec.describe "Bill page optional props", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /bills/:id" do
    # @lat: [[lazy-inertia-props#Lazy Inertia props#Current optional and deferred JSON props]]
    it "omits unread props from the initial Inertia page and keeps them in default bearer JSON" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale:)
      create(:legislator_vote, bill:)
      token = "bill-optional-props-token"
      create(:api_key, token:, bearer: user)

      get bill_path(bill)

      expect(inertia).to render_component(Pages::BILL)
      expect(inertia.props.keys).not_to include("legislator_votes", "districts")

      get bill_path(bill), headers: {"Authorization" => "Bearer #{token}"}

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body.keys).to include("legislator_votes", "districts")
      expect(response.parsed_body.fetch("legislator_votes")).to be_present
    end
  end

  describe "GET /bills/:id districts partial reload" do
    let(:partial_headers) do
      {
        "X-Inertia" => "true",
        "X-Inertia-Version" => InertiaRails.configuration.version.to_s,
        "X-Inertia-Partial-Component" => Pages::BILL,
        "X-Inertia-Partial-Data" => "districts"
      }
    end

    # @lat: [[lazy-inertia-props#Lazy Inertia props#Current optional and deferred JSON props]]
    it "returns the reader's districts in the bill's locale when the locale cookie names another" do
      cookie_locale, user = setup
      bill_locale = create(:sway_locale, city: "annapolis", state: "maryland", country: "united_states")
      bill_district = create(:district, sway_locale: bill_locale, name: "#{bill_locale.region_code}7")
      bill_legislator = create(:legislator, district: bill_district)
      create(:legislator_term, legislator: bill_legislator, district: bill_district)
      create(:user_legislator, user:, legislator: bill_legislator)
      bill = create(:bill, sway_locale: bill_locale)
      expect(cookie_locale).not_to eq(bill_locale)

      get bill_path(bill), headers: partial_headers

      districts = response.parsed_body.fetch("props").fetch("districts")
      expect(districts.map { |district| district.fetch("name") }).to eq([bill_district.name])
    end

    # @lat: [[lazy-inertia-props#Lazy Inertia props#Current optional and deferred JSON props]]
    it "falls back to the bill locale's at-large district for a signed-out reader" do
      cookie_locale, = setup
      bill_locale = create(:sway_locale, :congress)
      bill_at_large = create(:district, sway_locale: bill_locale, name: "US0")
      bill = create(:bill, sway_locale: bill_locale)
      expect(cookie_locale).not_to eq(bill_locale)
      session_hash.delete(:user_id)

      get bill_path(bill), headers: partial_headers

      districts = response.parsed_body.fetch("props").fetch("districts")
      expect(districts.map { |district| district.fetch("name") }).to eq([bill_at_large.name])
    end
  end

  describe "GET /bill_of_the_month" do
    # @lat: [[lazy-inertia-props#Lazy Inertia props#Current optional and deferred JSON props]]
    it "omits unread props from the initial Inertia page and keeps them in default bearer JSON" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale:, scheduled_release_date_utc: Time.zone.today)
      create(:legislator_vote, bill:)
      token = "bill-of-month-optional-props-token"
      create(:api_key, token:, bearer: user)

      get "/bill_of_the_month"

      expect(inertia).to render_component(Pages::BILL_OF_THE_MONTH)
      expect(inertia.props.keys).not_to include("legislator_votes", "districts")

      get "/bill_of_the_month", headers: {"Authorization" => "Bearer #{token}"}

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body.keys).to include("legislator_votes", "districts")
      expect(response.parsed_body.fetch("legislator_votes")).to be_present
    end
  end
end
