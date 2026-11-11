# frozen_string_literal: true

require "rails_helper"

# @lat: [[public-disclosure-pages#Why the carrier reviewer needs a page with no account]]
RSpec.describe "PrivacyPolicy", type: :request do
  describe "GET /privacy" do
    context "as an unauthenticated visitor" do
      it "returns 200" do
        get "/privacy"

        expect(response).to have_http_status(:ok)
      end

      it "does not redirect to login or root" do
        get "/privacy"

        expect(response).not_to be_redirect
      end

      it "renders the Privacy page component" do
        get "/privacy"

        expect(inertia).to render_component(Pages::PRIVACY)
      end

      it "renders under the public entrypoint, not the authenticated app bundle" do
        get "/privacy"

        expect(response.body).to match(%r{/assets/public-[^"']+\.js})
        expect(response.body).not_to match(%r{/assets/application-[^"']+\.js})
      end
    end

    context "as an authenticated user" do
      it "still returns 200 (page is open to everyone)" do
        get "/privacy"

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
