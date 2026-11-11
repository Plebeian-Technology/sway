# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/api/v1 — auth contract regressions (H4)", type: :request do
  include_context "with in-memory Rails.cache"

  describe "WebAuthn challenge — exactly-once consumption" do
    let(:phone) { "4105550001" }
    let!(:user) { create(:user, phone: phone) }
    let!(:passkey) { create(:passkey, user: user) }

    it "deletes the cache key on the first successful callback (no replay)" do
      # Step 1: get a challenge
      post "/api/v1/sessions/challenge",
        params: {session: {phone: phone}},
        as: :json
      expect(response).to have_http_status(:ok)
      challenge_id = json_body[:challenge_id]
      cache_key = "webauthn:challenge:#{challenge_id}"
      expect(Rails.cache.read(cache_key)).to be_present

      # Step 2: make WebAuthn verification succeed. A plain stand-in object is enough
      # for the verified credential: the controller reads only `sign_count` from it
      # before handing it to passkey.update!.
      verified = double("WebAuthn::Verified", sign_count: passkey.sign_count + 1)
      allow_any_instance_of(WebAuthn::RelyingParty).to receive(:verify_authentication)
        .and_return([verified, passkey])

      post "/api/v1/sessions/callback",
        params: {session: {challenge_id: challenge_id, credential: {id: "x", type: "public-key"}, platform: "ios"}},
        as: :json
      expect(response).to have_http_status(:ok)
      expect(json_body[:bearer_token]).to be_present

      # The challenge is gone once it has worked. It is used up inside the
      # User.transaction that wraps the verification and the ApiKey.create!.
      expect(Rails.cache.read(cache_key)).to be_nil

      # Step 3: replay returns 401 invalid_challenge.
      post "/api/v1/sessions/callback",
        params: {session: {challenge_id: challenge_id, credential: {id: "x", type: "public-key"}, platform: "ios"}},
        as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_challenge")
    end
  end

  describe "sms_verified_token — exactly-once consumption" do
    let(:phone) { "4105550002" }

    # @lat: [[identity-and-access#The phone number is the account]]

    it "/api/v1/registrations rejects an already-consumed sms_verified_token" do
      token = SmsVerificationToken.issue!(phone)
      # The first call only looks at the token; it gets used up later, in
      # /registrations/callback. Sending a token that no longer exists — deleted from
      # the cache here — gets a 401.
      Rails.cache.delete("#{SmsVerificationToken::KEY_PREFIX}:#{token}")

      post "/api/v1/registrations",
        params: {registration: {sms_verified_token: token, phone: phone}},
        as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_sms_token")
    end

    it "/api/v1/registrations rejects token bound to a different phone" do
      token = SmsVerificationToken.issue!(phone)
      post "/api/v1/registrations",
        params: {registration: {sms_verified_token: token, phone: "9998887777"}},
        as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_sms_token")
    end
  end

  describe "POST /api/v1/sessions/revoke_all" do
    let(:phone) { "4105550003" }
    let!(:user) { create(:user, phone: phone) }

    it "returns 204 and cascades expiry to all active ApiKeys" do
      headers = authenticate_as(user)
      # Create a 2nd device + ApiKey to ensure cascade hits both
      device2 = create(:user_device, user: user)
      ApiKey.create!(
        bearer: user,
        user_device: device2,
        token: "alt-#{SecureRandom.hex(8)}",
        expires_at: 90.days.from_now,
        name: "alt-key"
      )

      expect(user.user_devices.active.count).to eq(2)
      active_key_count = user.api_keys.where("expires_at IS NULL OR expires_at > ?", Time.current).count
      expect(active_key_count).to eq(2)

      post "/api/v1/sessions/revoke_all", headers: headers, as: :json
      expect(response).to have_http_status(:no_content)

      # All devices revoked
      expect(user.user_devices.active.count).to eq(0)
      # All ApiKeys expired (UserDevice#revoke! sets api_keys.expires_at = now)
      expect(user.api_keys.where("expires_at > ?", Time.current).count).to eq(0)
    end
  end

  # @lat: [[surfaces#The /api/v1 mobile API]]
  describe "bearer-only authentication for /api/v1 mobile account routes" do
    let(:user) { create(:user) }

    it "rejects protected /api/v1 endpoints when only a session cookie is provided" do
      sign_in(user)

      get "/api/v1/notification_preferences", as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("unauthorized")
      expect(json_body.dig(:error, :message)).to eq("Valid bearer token required")
    end

    it "rejects protected /api/v1 endpoints when only a refresh token cookie is provided" do
      refresh = create(:refresh_token, user: user)
      cookies_hash = {}
      allow_any_instance_of(ActionDispatch::Cookies::CookieJar).to receive(:encrypted).and_return(cookies_hash)
      cookies_hash[:refresh_token] = refresh.token

      get "/api/v1/notification_preferences", as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("unauthorized")
      expect(json_body.dig(:error, :message)).to eq("Valid bearer token required")
    end

    it "rejects protected /api/v1 mutation endpoints when presented with cookie session only" do
      sign_in(user)

      patch "/api/v1/devices/push_token",
        params: {push_token: "test-token"},
        as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("unauthorized")
      expect(json_body.dig(:error, :message)).to eq("Valid bearer token required")
    end

    it "rejects protected /api/v1 endpoints when an invalid bearer token is supplied alongside cookie session" do
      sign_in(user)

      get "/api/v1/notification_preferences",
        headers: {"Authorization" => "Bearer invalid-mobile-token"},
        as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("unauthorized")
    end

    it "rejects protected /api/v1 endpoints when an expired bearer token is supplied alongside cookie session" do
      expired_token = "expired-mobile-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: user, token: expired_token, expires_at: 1.day.ago)
      sign_in(user)

      get "/api/v1/notification_preferences",
        headers: {"Authorization" => "Bearer #{expired_token}"},
        as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("unauthorized")
    end

    it "succeeds on protected /api/v1 endpoints when a valid bearer token is supplied" do
      headers = authenticate_as(user)

      get "/api/v1/notification_preferences", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "attributes POST /api/v1/funnel_events strictly to bearer token user and never falls back to cookie user" do
      user_b = create(:user)
      sign_in(user)

      post "/api/v1/funnel_events",
        params: {step: "landing", visitor_token: "v-adv-1"},
        headers: {"Authorization" => "Bearer invalid-funnel-bearer"},
        as: :json
      expect(response).to have_http_status(:created)
      expect(RegistrationFunnelEvent.last.user).to be_nil

      raw_b = "funnel-token-b-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: user_b, token: raw_b)
      post "/api/v1/funnel_events",
        params: {step: "landing", visitor_token: "v-adv-2"},
        headers: {"Authorization" => "Bearer #{raw_b}"},
        as: :json
      expect(response).to have_http_status(:created)
      expect(RegistrationFunnelEvent.last.user).to eq(user_b)
    end
  end
end
