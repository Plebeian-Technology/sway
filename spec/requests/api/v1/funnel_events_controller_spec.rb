# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::FunnelEvents", type: :request do
  include_context "SessionDouble"

  describe "POST /api/v1/funnel_events" do
    let(:valid_params) do
      {
        step: "landing",
        visitor_token: "v-token-xyz-123",
        attribution_key: "s:campaign1",
        metadata: {
          screen_width: 390,
          screen_height: 844,
          browser: "Mobile Safari"
        }
      }
    end

    it "creates a new RegistrationFunnelEvent and returns 201" do
      expect {
        post "/api/v1/funnel_events", params: valid_params, as: :json
      }.to change(RegistrationFunnelEvent, :count).by(1)

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json["ok"]).to be true
      expect(json["visitor_token"]).to eq("v-token-xyz-123")

      event = RegistrationFunnelEvent.last
      expect(event&.visitor_token).to eq("v-token-xyz-123")
      expect(event&.step).to eq("landing")
      expect(event&.attribution_key).to eq("s:campaign1")
      expect(event&.metadata).to include("screen_width" => 390, "browser" => "Mobile Safari")
    end

    it "generates a visitor token if none provided" do
      post "/api/v1/funnel_events", params: {step: "landing"}, as: :json

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json["ok"]).to be true
      expect(json["visitor_token"]).to be_present

      event = RegistrationFunnelEvent.last
      expect(event&.visitor_token).to eq(json["visitor_token"])
    end

    it "replaces an oversized or malformed visitor_token with a fresh UUID and bounds attribution_key length" do
      malicious_token = "malicious<script>" * 20
      oversized_attr = "s:" + ("a" * 200)

      post "/api/v1/funnel_events",
        params: {step: "landing", visitor_token: malicious_token, attribution_key: oversized_attr},
        as: :json

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json["visitor_token"]).not_to eq(malicious_token)
      expect(json["visitor_token"]).to match(/\A[0-9a-f-]{36}\z/)

      event = RegistrationFunnelEvent.last
      expect(event&.visitor_token).to eq(json["visitor_token"])
      expect(event&.attribution_key&.length).to eq(100)
    end

    it "associates the signed in user when available" do
      user = create(:user)
      sign_in(user)

      expect {
        post "/api/v1/funnel_events", params: valid_params, as: :json
      }.to change(RegistrationFunnelEvent, :count).by(1)

      event = RegistrationFunnelEvent.last
      expect(event.user).to eq(user)
    end

    it "does not rotate RefreshToken via cookies when session[:user_id] is absent" do
      user = create(:user)
      rt = RefreshToken.create!(
        user: user,
        token: "unrotated-token",
        expires_at: 1.day.from_now,
        ip_address: "127.0.0.1",
        user_agent: "RSpec"
      )
      cookies_hash[:refresh_token] = rt.token

      post "/api/v1/funnel_events", params: valid_params, as: :json

      expect(response).to have_http_status(:created)
      expect(RegistrationFunnelEvent.last&.user).to be_nil
      expect(RefreshToken.find_by(id: rt.id)&.token).to eq("unrotated-token")
    end

    it "rejects invalid steps with unprocessable_entity" do
      post "/api/v1/funnel_events", params: {step: "invalid_unsupported_step"}, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      json = response.parsed_body
      expect(json["error"]).to be_present
      expect(json["error"]["code"]).to eq("invalid_step")
    end

    it "sanitizes metadata and rejects PII fields like phone_number or address" do
      params_with_pii = valid_params.merge(
        metadata: {
          phone_number: "+14105551234",
          address_line1: "100 North Holliday Street",
          screen_width: 390
        }
      )

      post "/api/v1/funnel_events", params: params_with_pii, as: :json
      expect(response).to have_http_status(:created)

      event = RegistrationFunnelEvent.last
      expect(event.metadata.keys).not_to include("phone_number", "address_line1")
      expect(event.metadata).to include("screen_width" => 390)
    end

    # @lat: [[registration-funnel-telemetry#Bot traffic classification]]
    it "classifies crawler and scripted user agents as bot traffic" do
      post "/api/v1/funnel_events",
        params: {step: "landing"},
        headers: {"HTTP_USER_AGENT" => "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"},
        as: :json

      expect(response).to have_http_status(:created)
      expect(RegistrationFunnelEvent.last&.bot).to be true
    end

    it "classifies genuine browser user agents as non-bot traffic" do
      post "/api/v1/funnel_events",
        params: {step: "landing"},
        headers: {"HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36"},
        as: :json

      expect(response).to have_http_status(:created)
      expect(RegistrationFunnelEvent.last&.bot).to be false
    end

    # @lat: [[registration-funnel-telemetry#Bot traffic classification#Verified users reclassify their visitor token]]
    it "reclassifies previous bot-flagged events when an authenticated human visitor posts an event" do
      token = "visitor-token-abc"
      RegistrationFunnelEvent.create!(visitor_token: token, step: :landing, bot: true)

      user = create(:user)
      sign_in(user)

      post "/api/v1/funnel_events",
        params: {step: "phone_submitted", visitor_token: token},
        headers: {"HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone)"},
        as: :json

      expect(response).to have_http_status(:created)
      expect(RegistrationFunnelEvent.where(visitor_token: token).pluck(:bot)).to all(be false)
    end

    # @lat: [[registration-funnel-telemetry#Ingestion API and rate limiting]]
    # @lat: [[registration-funnel-telemetry#Attribution preservation]]
    it "strips all FORBIDDEN_METADATA_KEYS, truncates oversized metadata values, and clamps to 20 keys" do
      fifty_keys = (1..25).to_h { |i| ["key_#{i}", "A" * 250] }
      forbidden = Api::V1::FunnelEventsController::FORBIDDEN_METADATA_KEYS.to_h { |k| [k, "secret"] }

      post "/api/v1/funnel_events",
        params: {step: "landing", metadata: fifty_keys.merge(forbidden).merge(nested: {bad: 1})},
        as: :json

      expect(response).to have_http_status(:created)
      event = RegistrationFunnelEvent.last
      expect(event.metadata.keys & Api::V1::FunnelEventsController::FORBIDDEN_METADATA_KEYS).to be_empty
      expect(event.metadata.keys).not_to include("nested")
      expect(event.metadata.keys.size).to be <= 20
      expect(event.metadata["key_1"].length).to eq(200)
    end

    it "enforces 60 requests/minute rate limit per IP and preserves attribution cookies across reset_session" do
      memory_store = ActiveSupport::Cache::MemoryStore.new
      ApplicationController::RATE_LIMIT_STORE.backend = memory_store
      begin
        60.times do
          post "/api/v1/funnel_events", params: {step: "landing"}, headers: {"REMOTE_ADDR" => "198.51.100.99"}, as: :json
          expect(response).to have_http_status(:created)
        end
        post "/api/v1/funnel_events", params: {step: "landing"}, headers: {"REMOTE_ADDR" => "198.51.100.99"}, as: :json
        expect(response).to have_http_status(:too_many_requests)
      ensure
        ApplicationController::RATE_LIMIT_STORE.backend = ActiveSupport::Cache::NullStore.new
      end

      user = create(:user)
      ctrl = ApplicationController.new
      ctrl.set_request!(ActionDispatch::TestRequest.create)
      ctrl.set_response!(ActionDispatch::TestResponse.create)
      session_store = {}
      allow(ctrl).to receive(:session).and_return(session_store)
      allow(ctrl).to receive(:reset_session) { session_store.clear }
      ctrl.send(:cookies)[:sway_attribution_key] = "s:adv_referral"
      ctrl.send(:cookies)[:sway_visitor_token] = "v-persist-auth"

      ctrl.send(:sign_in, user)
      expect(ctrl.send(:cookies)[:sway_attribution_key]).to eq("s:adv_referral")
      expect(ctrl.send(:cookies)[:sway_visitor_token]).to eq("v-persist-auth")
    end
  end
end

RSpec.describe "Api::V1::FunnelEvents session cookie isolation", type: :request do
  it "never writes the Rails session cookie on 201 or 422 telemetry responses even with flash present" do
    session_cookie_key = Rails.application.config.session_options.fetch(:key)

    post "/users/webauthn/registration/callback", params: {id: "stale"}
    expect(response).to have_http_status(:redirect)
    expect(Array(response.headers["Set-Cookie"]).join("\n")).to include("#{session_cookie_key}=")

    post "/api/v1/funnel_events", params: {step: "sms_verified"}, as: :json
    expect(response).to have_http_status(:created)
    expect(Array(response.headers["Set-Cookie"]).join("\n")).not_to include("#{session_cookie_key}=")
    expect(response.cookies["sway_visitor_token"]).to be_present

    post "/api/v1/funnel_events", params: {step: "invalid_step"}, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(Array(response.headers["Set-Cookie"]).join("\n")).not_to include("#{session_cookie_key}=")
  end
end
