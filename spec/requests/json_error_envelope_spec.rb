require "rails_helper"

# @lat: [[render-error-nonnil-fields-workaround#Why the envelope shape is pinned at the request-spec level, not per-controller]]
RSpec.describe "JSON error envelope (JsonErrorRenderable)", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "401 from the authentication gate" do
    it "renders { error: { code, message } } — never a flat error string" do
      get "/legislators", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      envelope = response.parsed_body["error"]
      expect(envelope).to be_a(Hash)
      expect(envelope).to include("code" => "unauthenticated")
      expect(envelope["message"]).to be_present
    end
  end

  describe "404 from a missing record" do
    it "renders { error: { code: 'not_found', message } } with a 404 status" do
      setup # signs in a registration-complete user so #show runs past the auth gate

      get "/organizations/0", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:not_found)
      envelope = response.parsed_body["error"]
      expect(envelope).to be_a(Hash)
      expect(envelope).to include(
        "code" => "not_found",
        "message" => "Organization not found."
      )
    end
  end
end
