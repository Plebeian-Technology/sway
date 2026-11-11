# frozen_string_literal: true

require "rails_helper"

# @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Client origin logging excludes credential payloads]]
RSpec.describe "Api::V1 passkey client-data origin logging", type: :request do
  include_context "WebAuthnDouble"

  include_context "with in-memory Rails.cache"

  let(:phone) { "4105550777" }
  let!(:user) do
    u = create(:user, phone: phone)
    complete_registration_with_active_link(u)
    u
  end

  def client_data(origin:, type: "webauthn.get", **extra)
    Base64.urlsafe_encode64(
      JSON.generate({type: type, origin: origin, challenge: "nonce"}.merge(extra)),
      padding: false
    )
  end

  def credential(client_data_json)
    {id: "x", type: "public-key", response: {clientDataJSON: client_data_json}}
  end

  before { allow(SwayLogging).to receive(:info).and_call_original }

  describe "POST /api/v1/sessions/callback" do
    let!(:passkey) { create(:passkey, user: user, external_id: fake_credential_id) }

    before do
      Rails.cache.write(
        "webauthn:challenge:origin1",
        {challenge: fake_challenge, phone: phone},
        expires_in: 5.minutes
      )
    end

    def sign_in_with(credential_payload)
      post "/api/v1/sessions/callback",
        params: {session: {challenge_id: "origin1", credential: credential_payload, platform: "ios"}},
        as: :json
    end

    it "logs the origin an iOS client reported" do
      sign_in_with(credential(client_data(origin: "https://dev.example.test")))

      expect(response).to have_http_status(:ok)
      expect(SwayLogging).to have_received(:info)
        .with(a_string_matching(%r{webauthn\.client_data .*origin="https://dev\.example\.test"}))
    end

    it "logs the verified Android origin and package name captured from Android Credential Manager" do
      sign_in_with(
        credential(
          client_data(
            origin: "android:apk-key-hash:-sYXRdwJA3hvue3mKpYrOZ9zSPC7b4mbgzJmdZEDO5w",
            androidPackageName: "vote.sway.app"
          )
        )
      )

      expect(response).to have_http_status(:ok)
      expect(SwayLogging).to have_received(:info)
        .with(a_string_matching(/origin="android:apk-key-hash:-sYXRdwJA3hvue3mKpYrOZ9zSPC7b4mbgzJmdZEDO5w"/))
      expect(SwayLogging).to have_received(:info)
        .with(a_string_matching(/android_package_name="vote\.sway\.app"/))
    end

    it "logs androidPackageName when an Android client sends one" do
      sign_in_with(
        credential(
          client_data(origin: "android:apk-key-hash:abc", androidPackageName: "vote.sway.app")
        )
      )

      expect(SwayLogging).to have_received(:info)
        .with(a_string_matching(/android_package_name="vote\.sway\.app"/))
    end

    it "does not log the challenge" do
      sign_in_with(credential(client_data(origin: "https://dev.example.test")))

      expect(SwayLogging).not_to have_received(:info).with(a_string_matching(/nonce/))
    end

    it "signs in normally when the credential carries no clientDataJSON" do
      sign_in_with({id: "x", type: "public-key"})

      expect(response).to have_http_status(:ok)
      expect(SwayLogging).not_to have_received(:info).with(a_string_matching(/webauthn\.client_data /))
    end

    it "warns and still signs in when clientDataJSON is undecodable" do
      allow(SwayLogging).to receive(:warn).and_call_original

      sign_in_with(credential("not-base64-$$$"))

      expect(response).to have_http_status(:ok)
      expect(SwayLogging).to have_received(:warn)
        .with(a_string_matching(/webauthn\.client_data\.unreadable/))
    end
  end

  describe "POST /api/v1/registrations/callback" do
    it "logs the origin the enrolling client reported" do
      enrolling_phone = "4105550778"
      token = SmsVerificationToken.issue!(enrolling_phone)
      Rails.cache.write(
        "webauthn:challenge:origin2",
        {challenge: fake_challenge, sms_verified_token: token, phone: enrolling_phone},
        expires_in: 5.minutes
      )

      post "/api/v1/registrations/callback",
        params: {
          registration: {
            challenge_id: "origin2",
            credential: credential(client_data(origin: "https://dev.example.test", type: "webauthn.create")),
            platform: "ios"
          }
        },
        as: :json

      expect(response).to have_http_status(:ok)
      expect(SwayLogging).to have_received(:info)
        .with(a_string_matching(%r{webauthn\.client_data .*origin="https://dev\.example\.test"}))
    end
  end

  describe "POST /api/v1/passkeys/callback" do
    it "logs the origin when an extra passkey is added" do
      headers = authenticate_as(user)
      token = SmsVerificationToken.issue!(phone)
      Rails.cache.write(
        "webauthn:challenge:origin3",
        {challenge: fake_challenge, user_id: user.id, phone: phone, sms_verified_token: token, label: "iPhone"},
        expires_in: 5.minutes
      )

      post "/api/v1/passkeys/callback",
        params: {
          passkey: {
            challenge_id: "origin3",
            credential: credential(client_data(origin: "https://dev.example.test", type: "webauthn.create"))
          }
        },
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)
      expect(SwayLogging).to have_received(:info)
        .with(a_string_matching(%r{webauthn\.client_data .*origin="https://dev\.example\.test"}))
    end
  end
end
