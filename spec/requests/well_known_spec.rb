require "rails_helper"

RSpec.describe "WellKnown", type: :request do
  describe "GET /.well-known/webauthn" do
    it "returns allowed WebAuthn origins for app.sway.vote" do
      host! "app.sway.vote"

      get "/.well-known/webauthn"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        {
          "origins" => ["https://sway.vote"],
        },
      )
    end

    it "returns an empty response for non-app hosts" do
      host! "www.sway.vote"

      get "/.well-known/webauthn"

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
    end
  end
end
