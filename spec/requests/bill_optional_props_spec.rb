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
