# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /" do
    context "when user is not signed in" do
      it "renders the Home component" do
        get root_path
        expect(inertia).to render_component Pages::HOME
      end

      it "passes name and isBubbles props" do
        get root_path
        expect(inertia).to have_props(name: "Sway", isBubbles: true)
      end

      # @lat: [[bad-request-responses#Bad request responses#JavaScript format probes answer 406]]
      it "returns 406 Not Acceptable when requested with a JavaScript Accept header or format parameter" do
        get root_path, headers: {"Accept" => "text/javascript"}
        expect(response).to have_http_status(:not_acceptable)

        get root_path, params: {format: "js"}, headers: {"Accept" => "text/javascript"}
        expect(response).to have_http_status(:not_acceptable)
      end

      # The page used to pass `params: params`, which copied every query-string
      # key into its props and overrode the small approved set shared across
      # pages. Keys a visitor invents must never appear in the Home page's
      # params prop.
      it "does not echo arbitrary query params into page props" do
        get root_path, params: {evil_key: "pwned"}

        expect(inertia).to render_component(Pages::HOME)
        expect(inertia.props[:params]).not_to have_key(:evil_key)
      end

      # @lat: [[identity-and-access#User JSON exposes only selected fields#Locale props are never cached once per browser]]
      it "preloads current_legislative_session without N+1 queries when building locale props" do
        SwayLocale.all.each do |loc|
          create(:legislative_session, sway_locale: loc, active: true)
        end

        statements = []
        callback = lambda do |_name, _start, _finish, _id, payload|
          sql = payload[:sql]
          statements << sql if sql.match?(/legislative_sessions/i) && !sql.match?(/sqlite_master|sqlite_temp_master/i)
        end

        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
          get root_path
        end

        expect(response).to have_http_status(:ok)
        expect(statements.size).to be <= 1
      end
    end

    context "when user is signed in with incomplete registration" do
      it "redirects to registration path" do
        _sway_locale, _user = setup_pre_registration

        get root_path
        expect(response).to redirect_to(sway_registration_index_path)
      end

      it "does not trust stale completion fields without an active pairing" do
        _sway_locale, user = setup_pre_registration
        user.update_columns(is_registration_complete: true, registration_status: "completed")

        get root_path

        expect(response).to redirect_to(sway_registration_index_path)
      end
    end

    context "when user is signed in with complete registration" do
      it "redirects to legislators path" do
        _sway_locale, user = setup_pre_registration
        create(:user_legislator, user: user)
        user.complete!

        get root_path
        expect(response).to redirect_to(legislators_path)
      end
    end
  end
end
