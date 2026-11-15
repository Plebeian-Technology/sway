# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Sessions", type: :request do
  include_context "with in-memory Rails.cache"

  let(:phone) { "4105550123" }
  let!(:user) { create(:user, phone: phone) }

  describe "POST /api/v1/sessions/challenge" do
    context "user has a passkey" do
      let!(:passkey) { create(:passkey, user: user) }

      it "answers flow: passkey with a challenge_id, nested options and a cache write" do
        post "/api/v1/sessions/challenge",
          params: {session: {phone: phone}},
          as: :json

        expect(response).to have_http_status(:ok)
        body = json_body
        expect(body[:flow]).to eq("passkey")
        expect(body[:challenge_id]).to be_present
        expect(body[:options][:challenge]).to be_present
        # The shape the WebAuthn spec defines for a sign-in request: rpId and
        # allowCredentials
        expect(body[:options][:rpId]).to be_present
        expect(body[:options][:allowCredentials]).to be_an(Array)

        cached = Rails.cache.read("webauthn:challenge:#{body[:challenge_id]}")
        expect(cached).to be_present
        expect(cached[:phone]).to eq(phone)
      end

      it "normalizes a formatted phone number to 10 digits before looking up the user" do
        post "/api/v1/sessions/challenge",
          params: {session: {phone: "+1 (410) 555-0123"}},
          as: :json

        expect(response).to have_http_status(:ok)
        body = json_body
        expect(body[:flow]).to eq("passkey")
        cached = Rails.cache.read("webauthn:challenge:#{body[:challenge_id]}")
        expect(cached[:phone]).to eq(phone)
      end
    end

    # @lat: [[decoy-challenge-non-disclosure#How the web sign-in flow (Users::Webauthn::SessionsController) achieves the same non-disclosure]]
    context "phone has an account but no passkey" do
      it "answers flow: sms and nothing else" do
        post "/api/v1/sessions/challenge",
          params: {session: {phone: phone}},
          as: :json

        expect(response).to have_http_status(:ok)
        expect(json_body).to eq({flow: "sms"})
      end

      it "writes no challenge to the cache" do
        expect(Rails.cache).not_to receive(:write)

        post "/api/v1/sessions/challenge",
          params: {session: {phone: phone}},
          as: :json
      end
    end

    context "phone unknown" do
      it "answers flow: sms, the same as a registered phone with no passkey" do
        post "/api/v1/sessions/challenge",
          params: {session: {phone: "9995551111"}},
          as: :json

        expect(response).to have_http_status(:ok)
        expect(json_body).to eq({flow: "sms"})
      end

      it "never touches Twilio from the challenge path" do
        expect(Twilio::REST::Client).not_to receive(:new)

        post "/api/v1/sessions/challenge",
          params: {session: {phone: "9995551111"}},
          as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    context "a phone that does have a passkey" do
      it "issues a fresh random challenge per request" do
        create(:passkey, user: user)

        challenges = Array.new(2) do
          post "/api/v1/sessions/challenge",
            params: {session: {phone: phone}},
            as: :json
          json_body[:options][:challenge]
        end
        expect(challenges.uniq.length).to eq(2)
      end
    end
  end

  # @lat: [[identity-and-access#The sign-in challenge says which ceremony to run]]
  describe "POST /api/v1/sessions/discoverable_challenge" do
    it "returns an empty-allowCredentials challenge and caches it with no phone" do
      post "/api/v1/sessions/discoverable_challenge", params: {}, as: :json

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body[:challenge_id]).to be_present
      expect(body[:challenge]).to be_present
      expect(body[:allowCredentials]).to eq([])

      cached = Rails.cache.read("webauthn:challenge:#{body[:challenge_id]}")
      expect(cached).to be_present
      expect(cached[:phone]).to be_nil
    end

    it "never sends an SMS from the challenge path" do
      expect(Twilio::REST::Client).not_to receive(:new)

      post "/api/v1/sessions/discoverable_challenge", params: {}, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "requires no phone parameter (identity-blind)" do
      # No :session and no :phone at all. The phone-first #challenge would answer 400,
      # because require(:session) finds nothing; this one has to succeed on an empty
      # body.
      post "/api/v1/sessions/discoverable_challenge", params: {}, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/sessions/callback" do
    it "returns 401 invalid_challenge when cache key is missing" do
      empty_credential = {}
      # @type var empty_credential: Hash[Symbol, untyped]
      post "/api/v1/sessions/callback",
        params: {session: {challenge_id: "deadbeef", credential: empty_credential, platform: "ios"}},
        as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_challenge")
    end

    # @lat: [[identity-and-access#The sign-in challenge says which ceremony to run]]
    it "returns 401 invalid_credentials when the cached phone names nobody" do
      Rails.cache.write(
        "webauthn:challenge:gone1",
        {challenge: "fake-challenge", phone: "9995551111"},
        expires_in: 5.minutes
      )

      post "/api/v1/sessions/callback",
        params: {session: {challenge_id: "gone1", credential: {id: "x", type: "public-key"}, platform: "ios"}},
        as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_credentials")
    end

    it "returns 401 invalid_credentials when the cached phone lost its last passkey mid-flight" do
      Rails.cache.write(
        "webauthn:challenge:gone2",
        {challenge: "fake-challenge", phone: phone},
        expires_in: 5.minutes
      )

      post "/api/v1/sessions/callback",
        params: {session: {challenge_id: "gone2", credential: {id: "x", type: "public-key"}, platform: "ios"}},
        as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_credentials")
    end

    context "when verification fails or passkey is unknown" do
      include_context "WebAuthnDouble"

      let!(:passkey) { create(:passkey, user: user, external_id: "different-cred-id") }

      it "returns 401 invalid_credentials and deletes the challenge when the credential id does not belong to the user" do
        Rails.cache.write(
          "webauthn:challenge:unknown-passkey",
          {challenge: fake_challenge, phone: phone},
          expires_in: 5.minutes
        )

        post "/api/v1/sessions/callback",
          params: {session: {challenge_id: "unknown-passkey", credential: {id: "unrecognized", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(json_body.dig(:error, :code)).to eq("invalid_credentials")
        expect(Rails.cache.read("webauthn:challenge:unknown-passkey")).to be_nil
      end

      it "deletes the challenge from Rails.cache when verify_authentication raises WebAuthn::Error" do
        Rails.cache.write(
          "webauthn:challenge:auth-fail",
          {challenge: fake_challenge, phone: phone},
          expires_in: 5.minutes
        )
        allow_any_instance_of(WebAuthn::RelyingParty)
          .to receive(:verify_authentication)
          .and_raise(WebAuthn::Error.new("invalid assertion"))

        post "/api/v1/sessions/callback",
          params: {session: {challenge_id: "auth-fail", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(json_body.dig(:error, :code)).to eq("invalid_credentials")
        expect(Rails.cache.read("webauthn:challenge:auth-fail")).to be_nil
      end
    end

    context "when verification succeeds" do
      let!(:passkey) { create(:passkey, user: user) }

      before do
        Rails.cache.write(
          "webauthn:challenge:abc123",
          {challenge: "fake-challenge", phone: phone},
          expires_in: 5.minutes
        )
        verified = double("WebAuthn::Verified", sign_count: passkey.sign_count + 1)
        allow_any_instance_of(WebAuthn::RelyingParty)
          .to receive(:verify_authentication)
          .and_return([verified, passkey])
      end

      it "updates passkey sign_count" do
        post "/api/v1/sessions/callback",
          params: {session: {challenge_id: "abc123", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:ok)
        expect(passkey.reload.sign_count).to eq(1)
      end

      it "updates passkey last_used_at" do
        expect {
          post "/api/v1/sessions/callback",
            params: {session: {challenge_id: "abc123", credential: {id: "x", type: "public-key"}, platform: "ios"}},
            as: :json
        }.to change { passkey.reload.last_used_at }.from(nil)
      end

      # When the stored challenge has no phone with it, the user is worked out from the
      # credential the device sent back rather than from a phone number, and a bearer
      # token is issued.
      it "resolves the user from the credential and issues a bearer (identity-blind)" do
        discoverable_passkey = create(:passkey, user: user, external_id: "disc-cred-1")
        Rails.cache.write(
          "webauthn:challenge:disc1",
          {challenge: "fake-challenge", phone: nil},
          expires_in: 5.minutes
        )
        verified = double("WebAuthn::Verified", sign_count: discoverable_passkey.sign_count + 1)
        allow_any_instance_of(WebAuthn::RelyingParty)
          .to receive(:verify_authentication)
          .and_return([verified, discoverable_passkey])

        post "/api/v1/sessions/callback",
          params: {session: {challenge_id: "disc1", credential: {id: "disc-cred-1", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:ok)
        expect(json_body[:bearer_token]).to be_present
        expect(json_body.dig(:user, :id)).to eq(user.id)
      end

      it "returns 401 invalid_credentials for a discoverable callback whose credential maps to no passkey" do
        Rails.cache.write(
          "webauthn:challenge:disc-unknown",
          {challenge: "fake-challenge", phone: nil},
          expires_in: 5.minutes
        )

        post "/api/v1/sessions/callback",
          params: {session: {challenge_id: "disc-unknown", credential: {id: "nope", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(json_body.dig(:error, :code)).to eq("invalid_credentials")
      end

      # The user data sent back with the bearer token goes through
      # build_bearer_token_payload, which calls user.to_sway_json — the same path
      # /registrations/callback takes. This checks the sensitive columns stay out of it.
      it "excludes sensitive user fields from the bearer-envelope user payload" do
        # Force the non-admin case, so is_admin is certain to be absent.
        User.send(:remove_const, :ADMIN_PHONES)
        User.const_set(:ADMIN_PHONES, ["+10000000000"])

        post "/api/v1/sessions/callback",
          params: {session: {challenge_id: "abc123", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:ok)
        user_payload = json_body[:user]
        %w[current_sign_in_ip last_sign_in_ip webauthn_id sign_in_count is_admin].each do |field|
          expect(user_payload).not_to have_key(field.to_sym)
          expect(user_payload).not_to have_key(field)
        end
      end
    end
  end

  # @lat: [[identity-and-access#The phone number is the account]]
  describe "POST /api/v1/sessions (removed)" do
    it "returns 404 — SMS-fallback login is not a supported auth path" do
      post "/api/v1/sessions",
        params: {session: {sms_verified_token: "anything", platform: "ios"}},
        as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/sessions/revoke_all (authenticated)" do
    it "returns 204 and revokes all active devices" do
      headers = authenticate_as(user)
      # Create another device to ensure revoke_all_devices! cascades
      create(:user_device, user: user)

      expect(user.user_devices.active.count).to eq(2)

      post "/api/v1/sessions/revoke_all", headers: headers, as: :json
      expect(response).to have_http_status(:no_content)
      expect(user.user_devices.active.count).to eq(0)
    end

    it "returns 401 when no bearer token is provided" do
      post "/api/v1/sessions/revoke_all", as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("unauthorized")
    end
  end

  # @lat: [[phone-verification-rate-limits#Why the sign-in challenge throttles two ways]]
  describe "rate limiting (account-enumeration bound)" do
    it "throttles /challenge per IP after 10 attempts (distinct phones, so the per-phone cap does not trip first)" do
      with_rate_limit_enabled(:sign_in) do
        11.times do |i|
          post "/api/v1/sessions/challenge",
            params: {session: {phone: "410555#{1000 + i}"}},
            as: :json
        end

        expect(response).to have_http_status(:too_many_requests)
        expect(json_body.dig(:error, :code)).to eq("rate_limited")
        expect(response.headers["Retry-After"]).to eq("300")
      end
    end

    it "throttles /challenge per phone and IP after 5 attempts" do
      with_rate_limit_enabled(:sign_in) do
        6.times do
          post "/api/v1/sessions/challenge",
            params: {session: {phone: phone}},
            headers: {"REMOTE_ADDR" => "10.0.0.1"},
            as: :json
        end

        expect(response).to have_http_status(:too_many_requests)
        expect(json_body.dig(:error, :code)).to eq("rate_limited")
        expect(response.headers["Retry-After"]).to eq("300")
      end
    end

    it "does not refuse a phone from a new IP after another IP used up its attempts for that phone" do
      with_rate_limit_enabled(:sign_in) do
        6.times do
          post "/api/v1/sessions/challenge",
            params: {session: {phone: phone}},
            headers: {"REMOTE_ADDR" => "10.0.0.1"},
            as: :json
        end

        post "/api/v1/sessions/challenge",
          params: {session: {phone: phone}},
          headers: {"REMOTE_ADDR" => "10.0.0.2"},
          as: :json

        expect(response).to have_http_status(:ok)
        expect(json_body[:flow]).to be_present
      end
    end

    # @lat: [[phone-verification-rate-limits#Why every phone-keyed limiter normalizes the number first]]
    it "buckets different formats of one phone into the same per-phone throttle" do
      with_rate_limit_enabled(:sign_in) do
        5.times do
          post "/api/v1/sessions/challenge",
            params: {session: {phone: "+1 (410) 555-1234"}},
            headers: {"REMOTE_ADDR" => "10.1.0.1"},
            as: :json
        end

        post "/api/v1/sessions/challenge",
          params: {session: {phone: "4105551234"}},
          headers: {"REMOTE_ADDR" => "10.1.0.1"},
          as: :json

        expect(response).to have_http_status(:too_many_requests)
        expect(json_body.dig(:error, :code)).to eq("rate_limited")
      end
    end
  end
end
