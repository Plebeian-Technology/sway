# frozen_string_literal: true

require "rails_helper"

# @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#Adding a passkey re-verifies by SMS first]]
RSpec.describe "Api::V1::Passkeys", type: :request do
  include_context "with in-memory Rails.cache"

  let(:phone) { "4105550999" }
  let!(:user) do
    u = create(:user, phone: phone)
    complete_registration_with_active_link(u)
    u
  end

  describe "POST /api/v1/passkeys" do
    it "issues discoverable registration options for a fresh SMS token" do
      headers = authenticate_as(user)
      token = SmsVerificationToken.issue!(phone)

      post "/api/v1/passkeys",
        params: {passkey: {sms_verified_token: token, label: "iPad"}},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body[:challenge_id]).to be_present
      expect(body.dig(:authenticatorSelection, :residentKey)).to eq("preferred")

      cached = Rails.cache.read("webauthn:challenge:#{body[:challenge_id]}")
      expect(cached[:user_id]).to eq(user.id)
      expect(cached[:sms_verified_token]).to eq(token)
    end

    it "excludes the account's existing passkeys from the ceremony" do
      headers = authenticate_as(user)
      existing = create(:passkey, user: user, external_id: "already-here")
      token = SmsVerificationToken.issue!(phone)

      expect_any_instance_of(WebAuthn::RelyingParty).to receive(
        :options_for_registration
      ).with(
        hash_including(exclude: [existing.external_id])
      ).and_call_original

      post "/api/v1/passkeys",
        params: {passkey: {sms_verified_token: token, label: "iPad"}},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)
    end

    it "returns 401 invalid_sms_token when the token is missing or unbound" do
      headers = authenticate_as(user)

      post "/api/v1/passkeys",
        params: {passkey: {sms_verified_token: "nope", label: "iPad"}},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_sms_token")
    end

    it "returns 401 invalid_sms_token when the token is bound to a different phone" do
      headers = authenticate_as(user)
      other_token = SmsVerificationToken.issue!("9998887777")

      post "/api/v1/passkeys",
        params: {passkey: {sms_verified_token: other_token, label: "iPad"}},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_sms_token")
    end

    it "returns 401 without a bearer token" do
      post "/api/v1/passkeys",
        params: {passkey: {sms_verified_token: "x"}},
        as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/passkeys/callback" do
    include_context "WebAuthnDouble"

    it "persists a new passkey on the current account" do
      headers = authenticate_as(user)
      token = SmsVerificationToken.issue!(phone)
      Rails.cache.write("webauthn:challenge:add1",
        {challenge: fake_challenge, user_id: user.id, phone: phone, sms_verified_token: token, label: "iPad"},
        expires_in: 5.minutes)

      expect {
        post "/api/v1/passkeys/callback",
          params: {passkey: {challenge_id: "add1", credential: {id: "x", type: "public-key"}}},
          headers: headers,
          as: :json
      }.to change { user.passkeys.count }.by(1)

      expect(response).to have_http_status(:ok)
      created = user.passkeys.order(:created_at).last
      expect(json_body[:id]).to eq(created.id)
      expect(created.label).to eq("iPad")
      expect(created.external_id).to eq(fake_credential_id)
    end

    it "rejects a duplicate device label" do
      headers = authenticate_as(user)
      create(:passkey, user: user, label: "iPad")
      token = SmsVerificationToken.issue!(phone)
      Rails.cache.write("webauthn:challenge:add2",
        {challenge: fake_challenge, user_id: user.id, phone: phone, sms_verified_token: token, label: "iPad"},
        expires_in: 5.minutes)

      expect {
        post "/api/v1/passkeys/callback",
          params: {passkey: {challenge_id: "add2", credential: {id: "x", type: "public-key"}}},
          headers: headers,
          as: :json
      }.not_to change { user.passkeys.count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body.dig(:error, :code)).to eq("invalid_passkey")
      expect(SmsVerificationToken.peek(token)).to be_present
    end

    it "disambiguates default passkey labels when enrolling multiple unlabeled passkeys" do
      headers = authenticate_as(user)
      create(:passkey, user: user, label: "New passkey")
      token = SmsVerificationToken.issue!(phone)
      Rails.cache.write("webauthn:challenge:add-default",
        {challenge: fake_challenge, user_id: user.id, phone: phone, sms_verified_token: token, label: nil},
        expires_in: 5.minutes)

      expect {
        post "/api/v1/passkeys/callback",
          params: {passkey: {challenge_id: "add-default", credential: {id: "x", type: "public-key"}}},
          headers: headers,
          as: :json
      }.to change { user.passkeys.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(json_body[:label]).to eq("New passkey 2")
    end

    it "rejects a second callback minted from the same sms_verified_token with 401 invalid_sms_token" do
      headers = authenticate_as(user)
      token = SmsVerificationToken.issue!(phone)

      post "/api/v1/passkeys",
        params: {passkey: {sms_verified_token: token, label: "iPad"}},
        headers: headers,
        as: :json
      first_challenge_id = json_body[:challenge_id]

      post "/api/v1/passkeys",
        params: {passkey: {sms_verified_token: token, label: "MacBook"}},
        headers: headers,
        as: :json
      second_challenge_id = json_body[:challenge_id]

      post "/api/v1/passkeys/callback",
        params: {passkey: {challenge_id: first_challenge_id, credential: {id: "x", type: "public-key"}}},
        headers: headers,
        as: :json
      expect(response).to have_http_status(:ok)

      expect {
        post "/api/v1/passkeys/callback",
          params: {passkey: {challenge_id: second_challenge_id, credential: {id: "y", type: "public-key"}}},
          headers: headers,
          as: :json
      }.not_to change { user.passkeys.count }

      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_sms_token")
      expect(Rails.cache.read("webauthn:challenge:#{second_challenge_id}")).to be_nil
    end

    it "deletes the challenge from Rails.cache when verify_registration raises WebAuthn::Error" do
      headers = authenticate_as(user)
      token = SmsVerificationToken.issue!(phone)
      Rails.cache.write("webauthn:challenge:add-fail",
        {challenge: fake_challenge, user_id: user.id, phone: phone, sms_verified_token: token, label: "iPad"},
        expires_in: 5.minutes)
      allow_any_instance_of(WebAuthn::RelyingParty).to receive(:verify_registration)
        .and_raise(WebAuthn::Error.new("bad attestation"))

      post "/api/v1/passkeys/callback",
        params: {passkey: {challenge_id: "add-fail", credential: {id: "x", type: "public-key"}}},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_credentials")
      expect(Rails.cache.read("webauthn:challenge:add-fail")).to be_nil
      expect(SmsVerificationToken.peek(token)).to be_present
    end

    it "returns 401 invalid_challenge when the challenge belongs to another user" do
      headers = authenticate_as(user)
      other = create(:user, phone: "5551239876")
      Rails.cache.write("webauthn:challenge:add3",
        {challenge: fake_challenge, user_id: other.id, phone: phone, sms_verified_token: "tok", label: "iPad"},
        expires_in: 5.minutes)

      post "/api/v1/passkeys/callback",
        params: {passkey: {challenge_id: "add3", credential: {id: "x", type: "public-key"}}},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_challenge")
    end
  end
end
