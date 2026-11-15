# frozen_string_literal: true

require "rails_helper"
require "support/malformed_webauthn_credentials"

RSpec.describe "WebAuthn origin verification", type: :request do
  include_context "SessionDouble"
  include_context "with in-memory Rails.cache"

  around do |example|
    with_app_config(:webauthn, allowed_origins: [MalformedWebauthnCredentials::ORIGIN], rp_id: nil) { example.run }
  end

  describe "POST /users/webauthn/registration/callback" do
    def post_web_enrollment(client, rp_id:)
      challenge = MalformedWebauthnCredentials.challenge
      session_hash[:verified_phone] = MalformedWebauthnCredentials::PHONE
      session_hash[:verified_phone_at] = Time.current.to_i
      session_hash[:current_registration] = {
        "challenge" => challenge,
        "user_attributes" => {"webauthn_id" => WebAuthn.generate_user_id}
      }
      credential = client.create(challenge: challenge, rp_id: rp_id, user_verified: true)

      post callback_users_webauthn_registration_index_path, params: credential, as: :json
    end

    def expect_web_enrollment_refused
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(Users::Webauthn::RegistrationController::VERIFICATION_FAILED_MESSAGE)
      expect(User.count).to eq(0)
      expect(Passkey.count).to eq(0)
      expect(session_hash[:current_registration]).to be_nil
    end

    # @lat: [[webauthn-origin-verification-tests#Web enrollment from another origin]]
    it "refuses a credential made on another origin" do
      post_web_enrollment(WebAuthn::FakeClient.new("https://evil.example"), rp_id: MalformedWebauthnCredentials::RP_ID)

      expect_web_enrollment_refused
    end

    # @lat: [[webauthn-origin-verification-tests#Web enrollment for another relying party]]
    it "refuses a credential made for another relying party id" do
      post_web_enrollment(MalformedWebauthnCredentials.client, rp_id: "evil.example")

      expect_web_enrollment_refused
    end
  end

  describe "POST /users/webauthn/sessions/callback" do
    # @lat: [[webauthn-origin-verification-tests#Web phone sign-in with a stale sign count]]
    it "refuses an assertion whose sign count is not above the stored one" do
      client = MalformedWebauthnCredentials.client
      passkey = MalformedWebauthnCredentials.enroll_user(client).passkeys.sole
      passkey.update!(sign_count: 5)
      challenge = MalformedWebauthnCredentials.challenge
      session_hash[:current_authentication] = {"challenge" => challenge, "phone" => MalformedWebauthnCredentials::PHONE}
      credential = MalformedWebauthnCredentials.assertion(client, challenge)

      post callback_users_webauthn_sessions_path, params: {publicKeyCredential: credential}, as: :json

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(Users::Webauthn::SessionsController::PASSKEY_VERIFICATION_FAILED_MESSAGE)
      expect(session_hash[:user_id]).to be_nil
      expect(passkey.reload.sign_count).to eq(5)
    end
  end

  describe "POST /api/v1/registrations/callback" do
    let(:configured_certificate) { Digest::SHA256.digest("sway-release-certificate") }
    let(:configured_fingerprint) { Digest::SHA256.hexdigest("sway-release-certificate").upcase.scan(/../).join(":") }
    let(:phone) { MalformedWebauthnCredentials::PHONE }
    let!(:sms_token) { SmsVerificationToken.issue!(phone) }

    around do |example|
      with_app_config(:mobile, android_cert_sha256_fingerprints: [configured_fingerprint]) { example.run }
    end

    def android_origin(certificate)
      "android:apk-key-hash:#{Base64.urlsafe_encode64(certificate, padding: false)}"
    end

    def post_mobile_enrollment(origin)
      challenge = MalformedWebauthnCredentials.challenge
      Rails.cache.write(
        "webauthn:challenge:android-origin",
        {challenge: challenge, phone: phone, sms_verified_token: sms_token, webauthn_id: WebAuthn.generate_user_id},
        expires_in: 5.minutes
      )
      credential = WebAuthn::FakeClient.new(origin)
        .create(challenge: challenge, rp_id: MalformedWebauthnCredentials::RP_ID, user_verified: true)

      post "/api/v1/registrations/callback",
        params: {registration: {challenge_id: "android-origin", credential: credential, platform: "android"}},
        as: :json
    end

    # @lat: [[webauthn-origin-verification-tests#Mobile enrollment from a configured Android app]]
    it "accepts a credential from the Android app whose certificate is configured" do
      post_mobile_enrollment(android_origin(configured_certificate))

      expect(response).to have_http_status(:ok)
      expect(json_body[:bearer_token]).to be_present
      expect(Passkey.where(user: User.find_by!(phone: phone)).count).to eq(1)
    end

    # @lat: [[webauthn-origin-verification-tests#Mobile enrollment from an unknown Android app]]
    it "refuses a credential from an Android app whose certificate is not configured" do
      post_mobile_enrollment(android_origin(Digest::SHA256.digest("someone-elses-certificate")))

      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_credentials")
      expect(User.find_by(phone: phone)).to be_nil
      expect(SmsVerificationToken.peek(sms_token)).to be_present
    end
  end
end
