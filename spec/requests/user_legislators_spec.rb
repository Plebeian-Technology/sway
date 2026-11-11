require "rails_helper"

RSpec.describe "UserLegislators", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /user_legislators" do
    it "renders JSON when signed in" do
      _sway_locale, user = setup
      expect(user).to be_persisted

      get user_legislators_path

      expect(response).to have_http_status(:ok)
    end

    it "redirects unauthenticated visitors" do
      # No setup call — no user signed in, session_hash is empty.
      get user_legislators_path

      expect(response).to have_http_status(:redirect).or have_http_status(:unauthorized)
    end
  end

  describe "POST /user_legislators" do
    it "runs SwayRegistrationService and redirects to legislators when signed in" do
      sway_locale, user = setup
      address = create(:address, city: sway_locale.city, region_code: sway_locale.region_code, country: sway_locale.country)
      create(:user_address, user:, address:)
      expect(user).to be_persisted

      allow_any_instance_of(SwayRegistrationService).to receive(:call).and_return(true)

      post user_legislators_path

      expect(response).to redirect_to(legislators_path)
    end

    it "rejects unauthenticated POSTs" do
      post user_legislators_path

      expect(response).to have_http_status(:unauthorized).or have_http_status(:redirect)
    end

    it "returns JSON 200 with the user's legislators when called with Accept: application/json" do
      sway_locale, user = setup
      address = create(:address, city: sway_locale.city, region_code: sway_locale.region_code, country: sway_locale.country)
      create(:user_address, user:, address:)
      expect(user).to be_persisted

      allow_any_instance_of(SwayRegistrationService).to receive(:call).and_return(true)

      post user_legislators_path, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "rejects POST when current_sway_locale is not in the user's sway_locales" do
      _sway_locale, user = setup
      foreign_address = create(:address, city: "Austin", region_code: "TX", country: "United States")
      create(:user_address, user:, address: foreign_address)

      expect(SwayRegistrationService).not_to receive(:new)

      post user_legislators_path, headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:forbidden)

      post user_legislators_path
      expect(response).to redirect_to(legislators_path)
      expect(flash[:alert]).to be_present
    end
  end
end
