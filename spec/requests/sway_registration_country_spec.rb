# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /sway_registration with a spelled-out United States", type: :request do
  include_context "SessionDouble"

  let!(:user) { create(:user, is_registration_complete: false, registration_status: "pending") }

  before do
    sign_in(user)
    allow_any_instance_of(SwayRegistrationService).to receive(:call) # rubocop:disable RSpec/AnyInstance
  end

  it "builds the city and state locales under the United States" do
    post "/sway_registration", params: {
      sway_registration: {
        street: "100 N Holliday St",
        street2: "",
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21202",
        country: "USA",
        latitude: 39.29105,
        longitude: -76.61069
      }
    }, headers: {"Accept" => "application/json"}

    expect(response).to have_http_status(:ok)
    expect(user.reload.sway_locales.map(&:name)).to include(
      "baltimore-maryland-united_states",
      "maryland-maryland-united_states"
    )
    expect(SwayLocale.where(country: "usa")).to be_empty
  end
end
