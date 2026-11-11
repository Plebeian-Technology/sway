# frozen_string_literal: true

require "rails_helper"

# The /download marketing page, which shows App Store and Play Store install
# badges. Anyone can visit it, signed in or not. It is rendered by plain ERB,
# not Inertia, because this page must work without the React bundle — app store
# reviewers and search crawlers need to find the badges.
RSpec.describe "Marketing", type: :request do
  describe "GET /download" do
    context "as an unauthenticated visitor" do
      # MarketingController falls back to the literal "<APPLE_APP_ID>"
      # placeholder, and the badge template hides the Apple link whenever the
      # ID still looks like a placeholder. Supply a realistic numeric ID so
      # these examples follow the same path production does.
      around do |example|
        with_app_config(:mobile, apple_app_store_id: "1234567890") { example.run }
      end

      it "returns 200" do
        get "/download"
        expect(response).to have_http_status(:ok)
      end

      it "renders the page (no auth redirect)" do
        get "/download"
        expect(response).not_to be_redirect
      end

      it "includes the Apple App Store badge SVG" do
        get "/download"
        expect(response.body).to include("apple-app-store-badge")
      end

      it "includes the Google Play badge SVG" do
        get "/download"
        expect(response.body).to include("google-play-badge")
      end

      it "includes a primary 'Get Sway' headline" do
        get "/download"
        expect(response.body).to include("Get Sway")
      end

      it "uses rel=noopener on the store anchors (security hygiene)" do
        get "/download"
        expect(response.body).to match(/rel="[^"]*noopener[^"]*"/)
      end

      it "links the App Store badge through to apps.apple.com (placeholder ID acceptable)" do
        get "/download"
        expect(response.body).to match(%r{https://apps\.apple\.com/app/id[^"]+})
      end

      it "links the Play Store badge through to play.google.com with package name vote.sway.app" do
        get "/download"
        expect(response.body).to include("play.google.com/store/apps/details?id=vote.sway.app")
      end

      it "carries the stubbed store id through to the App Store link, proving the read goes through the declared setting" do
        get "/download"
        expect(response.body).to include("apps.apple.com/app/id1234567890")
      end
    end

    # @lat: [[download-page-app-store-id-placeholder#Why /download degrades instead of erroring with no App Store id set]]
    context "with no APPLE_APP_STORE_ID set" do
      it "still returns 200 and omits the App Store anchor for the declared placeholder" do
        get "/download"
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("apps.apple.com/app/id")
        expect(response.body).to include("play.google.com/store/apps/details?id=vote.sway.app")
      end
    end

    context "as an authenticated user" do
      it "still returns 200 (page is open to everyone)" do
        # Marketing pages are public. A signed-in user can still land on
        # /download from a shared link, a deep link, and so on.
        get "/download"
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
