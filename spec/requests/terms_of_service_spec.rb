# frozen_string_literal: true

require "rails_helper"

# @lat: [[public-disclosure-pages#Why the carrier reviewer needs a page with no account]]
RSpec.describe "TermsOfService", type: :request do
  describe "GET /terms" do
    context "as an unauthenticated visitor" do
      it "returns 200" do
        get "/terms"

        expect(response).to have_http_status(:ok)
      end

      it "does not redirect to login or root" do
        get "/terms"

        expect(response).not_to be_redirect
      end

      it "renders the Terms page component" do
        get "/terms"

        expect(inertia).to render_component(Pages::TERMS)
      end

      it "renders under the public entrypoint, not the authenticated app bundle" do
        get "/terms"

        expect(response.body).to match(%r{/assets/public-[^"']+\.js})
        expect(response.body).not_to match(%r{/assets/application-[^"']+\.js})
      end
    end

    context "as an authenticated user" do
      it "still returns 200 (page is open to everyone)" do
        get "/terms"

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
