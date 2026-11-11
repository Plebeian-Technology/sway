# frozen_string_literal: true

require "rails_helper"

# @lat: [[theme-font-hrefs#Why the layout requests only the active theme's fonts]]
RSpec.describe "Per-theme webfonts", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  # Put a plain value straight into SessionDouble's store: the stand-in
  # cookies.signed jar on the controller side reads it back as it is.
  # spec/requests/users/preferences_spec.rb does the same.
  def visit_with_theme(theme_id)
    _, _user = setup
    cookies_hash[:sway_theme_id] = theme_id if theme_id
    get "/bills"
  end

  # @lat: [[theme-font-hrefs#Why the request specs assert on the link tag, not the body text]]
  def emitted_font_link
    response.body[/<link\s[^>]*data-theme-fonts[^>]*>/]
  end

  describe "the themes that ship a webfont" do
    it "requests Ballot's Barlow superfamily when Ballot is active" do
      visit_with_theme("ballot")

      expect(response.body).to include('data-theme="ballot"')
      expect(emitted_font_link).to include("Barlow+Semi+Condensed")
      expect(response.body).to include("fonts.gstatic.com")
    end

    it "requests Corner Store's wood type when Corner Store is active" do
      visit_with_theme("cornerstore")

      expect(response.body).to include('data-theme="cornerstore"')
      expect(emitted_font_link).to include("Alfa+Slab+One")
      expect(emitted_font_link).to include("Libre+Franklin")
    end

    it "keeps serving Banner's existing faces" do
      visit_with_theme("banner")

      expect(emitted_font_link).to include("Mona+Sans")
    end

    it "requests Inter and IBM Plex Mono when Monochrome is active" do
      visit_with_theme("monochrome")

      expect(response.body).to include('data-theme="monochrome"')
      expect(emitted_font_link).to include("family=IBM+Plex+Mono")
      expect(emitted_font_link).to include("family=Inter")
    end

    it "requests Inter and IBM Plex Mono when Service Manual is active" do
      visit_with_theme("service-manual")

      expect(response.body).to include('data-theme="service-manual"')
      expect(emitted_font_link).to include("family=IBM+Plex+Mono")
      expect(emitted_font_link).to include("family=Inter")
    end

    it "requests Inter and IBM Plex Mono when Swiss Notice is active" do
      visit_with_theme("swiss-grid")

      expect(response.body).to include('data-theme="swiss-grid"')
      expect(emitted_font_link).to include("family=IBM+Plex+Mono")
      expect(emitted_font_link).to include("family=Inter")
    end

    it "requests exactly one theme's faces, never another theme's" do
      visit_with_theme("ballot")

      expect(emitted_font_link).not_to include("Alfa+Slab+One")
      expect(emitted_font_link).not_to include("Mona+Sans")
    end
  end

  describe "the themes that ship none" do
    it "requests no webfont at all on the default theme (sway)" do
      visit_with_theme(nil)

      expect(response.body).to include('data-theme="sway"')
      expect(emitted_font_link).to be_nil
      expect(response.body).not_to include("preconnect")
    end
  end

  # @lat: [[theme-font-hrefs#Why the shared theme prop carries the whole font map]]
  describe "switching themes without a page load" do
    it "gives the font link a handle the client can find" do
      visit_with_theme("ballot")

      expect(response.body).to include("data-theme-fonts")
    end

    it "ships the full href map on the theme prop, not just the active theme's" do
      _, _user = setup

      get "/bills"

      expect(inertia).to render_component(Pages::BILLS)
      font_hrefs = inertia.props[:theme][:font_hrefs]
      expect(font_hrefs.keys.map(&:to_s)).to match_array(ThemeHelper::THEME_FONT_HREFS.keys)
      expect(font_hrefs[:cornerstore]).to eq(ThemeHelper::THEME_FONT_HREFS["cornerstore"])
    end

    it "ships the map even on a theme that has no webfont of its own" do
      visit_with_theme(nil)

      expect(inertia).to render_component(Pages::BILLS)
      expect(inertia.props[:theme][:id]).to eq("sway")
      expect(inertia.props[:theme][:font_hrefs]).to be_present
    end
  end

  describe "theme registration" do
    it "accepts the new theme ids through the preferences allowlist" do
      _, _user = setup

      %w[ballot cornerstore monochrome service-manual sway swiss-grid].each do |theme_id|
        patch "/users/preferences", params: {preferences: {theme_id: theme_id}}

        expect(response).to have_http_status(:found)
        expect(cookies_hash[:sway_theme_id]).to include(value: theme_id)
      end
    end

    it "keeps every registered theme's font mapping resolvable or absent, never stale" do
      # A theme id in the font map that is not a real theme would simply never
      # be used; checking here keeps the two lists in step.
      expect(ThemeHelper::THEME_FONT_HREFS.keys).to all(be_in(ThemeHelper::VALID_THEME_IDS))
    end
  end
end
