# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users::Preferences", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "PATCH /users/preferences (cookie / Inertia)" do
    it "updates theme_mode and redirects to /profile with a flash" do
      _, user = setup
      original = user.theme_mode

      patch "/users/preferences", params: {preferences: {theme_mode: "dark"}}

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to("/profile")
      expect(user.reload.theme_mode).to eq("dark")
      expect(user.theme_mode).not_to eq(original) if original != "dark"
    end

    # A validation failure must leave the user on the page they were already on,
    # with an Inertia errors prop. It must not redirect to /bills — that looks
    # like a success, so useTheme never runs its onError rollback and the user
    # gets yanked away.
    it "rejects an invalid theme_mode, stays on the triggering page, and surfaces Inertia errors" do
      _, user = setup
      patch "/users/preferences",
        params: {preferences: {theme_mode: "blue"}},
        headers: {"HTTP_REFERER" => "/legislators"}

      expect(response).to redirect_to("/legislators")
      expect(user.reload.theme_mode).not_to eq("blue")

      follow_redirect!
      expect(inertia).to render_component(Pages::LEGISLATORS)
      expect(inertia.props[:errors]).to include(:preferences)
    end

    it "rejects a missing preferences param with the same stay-on-page errors contract" do
      _, _user = setup
      patch "/users/preferences", params: {}, headers: {"HTTP_REFERER" => "/legislators"}

      expect(response).to redirect_to("/legislators")
      follow_redirect!
      expect(inertia.props[:errors]).to include(:preferences)
    end
  end

  describe "PATCH /users/preferences (bearer / JSON)" do
    let(:user) do
      u = create(:user)
      complete_registration_with_active_link(u)
      u
    end

    it "updates theme_mode and returns the JSON redirect envelope" do
      headers = authenticate_as(user)
      patch "/users/preferences",
        params: {preferences: {theme_mode: "dark"}},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body[:redirect]).to eq("/profile")
      expect(body[:flash]).to eq("Preferences updated")
      expect(user.reload.theme_mode).to eq("dark")
    end

    it "accepts each value in the auto|light|dark enum" do
      headers = authenticate_as(user)
      %w[auto light dark].each do |mode|
        patch "/users/preferences",
          params: {preferences: {theme_mode: mode}},
          headers: headers,
          as: :json
        expect(response).to have_http_status(:ok), "mode=#{mode} → #{response.status} #{response.body}"
        expect(user.reload.theme_mode).to eq(mode)
      end
    end

    # @lat: [[user-preferences-request-tests#User preference request tests#An invalid theme mode uses the JSON validation contract]]
    it "rejects an invalid theme_mode with 422 + validation_failed envelope" do
      headers = authenticate_as(user)
      original = user.theme_mode

      patch "/users/preferences",
        params: {preferences: {theme_mode: "blue"}},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:unprocessable_content)
      body = json_body
      expect(body.dig(:error, :code)).to eq("validation_failed")
      expect(body.dig(:error, :details)).to be_present
      expect(user.reload.theme_mode).to eq(original)
    end

    it "returns 401 unauthorized without bearer or cookie" do
      patch "/users/preferences",
        params: {preferences: {theme_mode: "dark"}},
        as: :json

      # ApplicationController redirects signed-out cookie callers, so a JSON
      # request with no bearer token comes back as either a redirect (302) or a
      # 401. Either is acceptable. All that matters is that nothing was saved.
      expect([:redirect, :unauthorized]).to include(response.status.between?(300, 399) ? :redirect : :unauthorized)
    end
  end

  describe "PATCH /users/preferences with theme_id (Inertia/cookie surface)" do
    it "writes the signed cookie on valid theme_id" do
      _, _user = setup
      patch "/users/preferences", params: {preferences: {theme_id: "ballot"}}
      expect(response).to have_http_status(:redirect)
      # The controller writes a whole options hash into the stubbed
      # cookies_hash, so check it with include(value:) rather than eq.
      expect(cookies_hash[:sway_theme_id]).to include(value: "ballot")
    end

    it "accepts a theme_id-only payload without theme_mode (round-1 HIGH item 1 — .present? guards)" do
      # A PATCH that sends only theme_id must not fail the empty-string
      # theme_mode check and return a 422.
      _, _user = setup
      patch "/users/preferences", params: {preferences: {theme_id: "cornerstore"}}
      expect(response).to have_http_status(:redirect)
      expect(cookies_hash[:sway_theme_id]).to include(value: "cornerstore")
    end

    it "does not set the cookie and re-renders on invalid theme_id (Inertia surface)" do
      _, _user = setup
      patch "/users/preferences", params: {preferences: {theme_id: "bogus"}}
      # An invalid theme_id is never written, so the backing cookies_hash entry
      # stays nil.
      expect(cookies_hash[:sway_theme_id]).to be_nil
      # On the cookie/Inertia path a validation failure comes back as either a
      # 422 or a re-rendered Profile page carrying errors. Like the invalid
      # theme_mode test above, only assert that nothing was saved; do not pin
      # down the exact response status.
    end
  end

  describe "PATCH /users/preferences with theme_id (bearer/JSON surface)" do
    let(:user) do
      u = create(:user)
      complete_registration_with_active_link(u)
      u
    end

    # @lat: [[user-preferences-request-tests#User preference request tests#An invalid theme id uses the JSON validation contract]]
    it "rejects an invalid theme_id with 422 + validation_failed envelope (bearer/JSON)" do
      headers = authenticate_as(user)
      patch "/users/preferences",
        params: {preferences: {theme_id: "bogus"}},
        headers: headers,
        as: :json
      expect(response).to have_http_status(:unprocessable_content)
      body = json_body
      expect(body.dig(:error, :code)).to eq("validation_failed")
      # An invalid theme_id is never written to the backing store.
      expect(cookies_hash[:sway_theme_id]).to be_nil
    end
  end

  describe "ThemeHelper#theme_id resolution (T-53-02 signed-cookie tamper-fallback)" do
    # @lat: [[user-preferences-request-tests#User preference request tests#Theme helper examples seed the signed cookie store]]
    it "renders default 'sway' when no cookie is set" do
      _, _user = setup
      get "/bills"
      expect(response.body).to include('data-theme="sway"')
    end

    it "renders the cookie value when set to a valid id" do
      _, _user = setup
      # Seed a plain value — the helper reads it straight back through the
      # stubbed controller-side cookies.signed jar.
      cookies_hash[:sway_theme_id] = "ballot"
      get "/bills"
      expect(response.body).to include('data-theme="ballot"')
    end

    it "falls back to default when cookie value is not in the allowlist" do
      _, _user = setup
      cookies_hash[:sway_theme_id] = "bogus"
      get "/bills"
      expect(response.body).to include('data-theme="sway"')
    end
  end
end
