# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /up (rails/health#show — reachability heartbeat)", type: :request do
  it "returns 200 for GET without authentication" do
    get "/up"

    expect(response).to have_http_status(:ok)
  end

  it "returns 200 for HEAD without authentication (reachability probe uses HEAD)" do
    head "/up"

    expect(response).to have_http_status(:ok)
    expect(response.body).to be_blank
  end

  it "is not rate-limited so the 30s-interval heartbeat never gets 429" do
    # rails/health#show does not inherit from Sway's ApplicationController, and
    # it is not one of the rate-limited actions (sign_in, sign_up,
    # phone_verify, email_verify, csp_report, org_invite). Hit it 50 times and
    # check that no 429 comes back.
    50.times.find do
      get "/up"
      response.status == 429
    end

    expect(response).to have_http_status(:ok)
  end
end
