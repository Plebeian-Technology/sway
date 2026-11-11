require "rails_helper"

RSpec.describe "SwayLocales", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /sway_locales" do
    it "renders the locale list JSON when signed out (auth skipped on this controller)" do
      # SwayLocalesController skips authenticate_sway_user! so anonymous GETs
      # still succeed and see the public locale list.
      create(:sway_locale, city: "baltimore", state: "MD", country: "United States")

      get sway_locales_path

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to be_an(Array)
    end

    it "includes declared locales and excludes undeclared locales when signed out" do
      declared_locale = create(:sway_locale, :baltimore)
      undeclared_locale = create(:sway_locale, city: "bethesda", state: "MD", country: "United States")

      get sway_locales_path

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body).pluck("id")
      expect(ids).to include(declared_locale.id)
      expect(ids).not_to include(undeclared_locale.id)
    end

    it "renders the signed-in user's locale list when signed in" do
      _sway_locale, user = setup
      expect(user).to be_persisted

      get sway_locales_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /sway_locales/:id" do
    it "renders a single locale's JSON without a persistent cookie side-effect" do
      sway_locale = create(
        :sway_locale,
        city: "baltimore",
        state: "MD",
        country: "United States"
      )

      get sway_locale_path(sway_locale)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to be_a(Hash)
      # @lat: [[sway-locale-id-param-cookie-guard#Why SwayLocalesController.show never writes the cookie either]]
      expect(cookies_hash).not_to have_key(:sway_locale_id)
    end

    # SwayLocale.find raised RecordNotFound before the `|| default_locale`
    # fallback ever got to run, so an unknown or stale id came back 404.
    # find_by returns nil instead, which lets the fallback serve the default
    # locale.
    it "falls back to the default locale for an unknown id instead of 404ing" do
      # SwayLocale.default_locale ends up being this congress record. Hold the
      # created record in a local so the id assertion has a non-nil value to
      # type-check against.
      default = create(:sway_locale, city: "congress", state: "congress", country: "united_states")

      get sway_locale_path(999999)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(default.id)
    end
  end
end
