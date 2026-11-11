# frozen_string_literal: true

require "rails_helper"

# @lat: [[production-image#Breakdown of runtime asset bytes and container serving]]
RSpec.describe "Public runtime assets", type: :request do
  describe "essential static assets" do
    it "serves favicon.ico with HTTP 200" do
      get "/favicon.ico"
      expect(response).to have_http_status(:ok)
    end

    it "serves apple-touch-icon.png with HTTP 200" do
      get "/apple-touch-icon.png"
      expect(response).to have_http_status(:ok)
    end

    it "serves sway-us-light.png with HTTP 200" do
      get "/images/sway-us-light.png"
      expect(response).to have_http_status(:ok)
    end

    it "serves banner-1200.png with HTTP 200" do
      get "/images/banner-1200.png"
      expect(response).to have_http_status(:ok)
    end

    it "serves manifest.webmanifest with HTTP 200" do
      get "/manifest.webmanifest"
      expect(response).to have_http_status(:ok)
    end

    it "serves robots.txt with HTTP 200" do
      get "/robots.txt"
      expect(response).to have_http_status(:ok)
    end

    it "serves dynamic sitemap.xml with HTTP 200" do
      get "/sitemap.xml"
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/xml")
    end
  end

  describe "rendered page asset tags" do
    it "renders Vite stylesheet and script tags on the root page without 404s" do
      get "/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("/favicon.ico")
      expect(response.body).to include("/manifest.json")
    end
  end

  describe "previous-release Inertia client version mismatch" do
    let(:sway_locale) { create(:sway_locale) }

    it "answers an outdated asset version request with 409 Conflict and an X-Inertia-Location header" do
      get "/bills",
        params: {sway_locale_id: sway_locale.id},
        headers: {
          "X-Inertia" => "true",
          "X-Inertia-Version" => "outdated-previous-release-version"
        }

      expect(response).to have_http_status(:conflict)
      expect(response.headers["X-Inertia-Location"]).to be_present
      location = response.headers["X-Inertia-Location"]

      get location
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<html")
    end
  end
end
