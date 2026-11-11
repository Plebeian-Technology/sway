require "rails_helper"

RSpec.describe "Authenticated controllers, JSON requests, no session", type: :request do
  describe "GET /legislators with no session" do
    it "returns 401 unauthenticated JSON when Accept: application/json" do
      get "/legislators", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("application/json")
      # Errors are wrapped as { error: { code, message } }.
      expect(response.parsed_body["error"]).to include(
        "code" => "unauthenticated",
        "message" => "Sign in to continue."
      )
    end

    it "still redirects HTML callers to root (existing browser behavior preserved)" do
      get "/legislators", headers: {"Accept" => "text/html"}

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(root_url)
    end
  end

  describe "GET /legislators with format=json and an incomplete-registration user" do
    include_context "SessionDouble"

    it "returns 403 registration_incomplete JSON instead of redirecting to /sway-registration" do
      address = create(:address)
      sway_locale = create(:sway_locale,
        city: address.city,
        state: address.region_code,
        country: address.country)
      user = create(:user, is_registration_complete: false)
      sign_in(user)
      session_hash[:sway_locale_id] = sway_locale.id

      get "/legislators", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:forbidden)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body["error"]).to include(
        "code" => "registration_incomplete",
        "message" => "Finish registration to continue."
      )
    end
  end
end
