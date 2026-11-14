# frozen_string_literal: true

require "rails_helper"
require "support/malformed_webauthn_credentials"

RSpec.describe "Malformed passkey credentials", type: :request do
  include_context "SessionDouble"
  include_context "with in-memory Rails.cache"

  around do |example|
    with_app_config(:webauthn, allowed_origins: [MalformedWebauthnCredentials::ORIGIN], rp_id: nil) { example.run }
  end

  describe "POST /users/webauthn/registration/callback" do
    # @lat: [[malformed-passkey-credential-tests#Web enrollment]]
    MalformedWebauthnCredentials::REGISTRATION_CORRUPTIONS.each do |corruption, corrupt|
      it "redirects with the verification-failed alert for #{corruption}" do
        client = MalformedWebauthnCredentials.client
        challenge = MalformedWebauthnCredentials.challenge
        session_hash[:verified_phone] = MalformedWebauthnCredentials::PHONE
        session_hash[:verified_phone_at] = Time.current.to_i
        session_hash[:current_registration] = {
          "challenge" => challenge,
          "user_attributes" => {"webauthn_id" => WebAuthn.generate_user_id}
        }
        credential = corrupt.call(MalformedWebauthnCredentials.registration(client, challenge))

        expect {
          post callback_users_webauthn_registration_index_path, params: credential, as: :json
        }.not_to(change { [User.count, Passkey.count] })

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(MalformedWebauthnCredentials::WEB_REJECTION_MESSAGE)
        expect(session_hash[:current_registration]).to be_nil
      end
    end
  end

  describe "POST /users/webauthn/sessions/callback" do
    # @lat: [[malformed-passkey-credential-tests#Web phone sign-in]]
    MalformedWebauthnCredentials::ASSERTION_CORRUPTIONS.each do |corruption, corrupt|
      it "redirects with the verification-failed alert for #{corruption}" do
        client = MalformedWebauthnCredentials.client
        challenge = MalformedWebauthnCredentials.challenge
        MalformedWebauthnCredentials.enroll_user(client)
        session_hash[:current_authentication] = {"challenge" => challenge, "phone" => MalformedWebauthnCredentials::PHONE}
        credential = corrupt.call(MalformedWebauthnCredentials.assertion(client, challenge))

        post callback_users_webauthn_sessions_path, params: {publicKeyCredential: credential}, as: :json

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(MalformedWebauthnCredentials::WEB_REJECTION_MESSAGE)
        expect(session_hash[:user_id]).to be_nil
        expect(session_hash[:current_authentication]).to be_nil
      end
    end
  end

  describe "POST /users/webauthn/sessions/discoverable_callback" do
    # @lat: [[malformed-passkey-credential-tests#Web discoverable sign-in]]
    MalformedWebauthnCredentials::ASSERTION_CORRUPTIONS.each do |corruption, corrupt|
      it "redirects with the verification-failed alert for #{corruption}" do
        client = MalformedWebauthnCredentials.client
        challenge = MalformedWebauthnCredentials.challenge
        MalformedWebauthnCredentials.enroll_user(client)
        session_hash[:discoverable_authentication] = {"challenge" => challenge}
        credential = corrupt.call(MalformedWebauthnCredentials.assertion(client, challenge))

        post discoverable_callback_users_webauthn_sessions_path, params: {publicKeyCredential: credential}, as: :json

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(MalformedWebauthnCredentials::WEB_REJECTION_MESSAGE)
        expect(session_hash[:user_id]).to be_nil
        expect(session_hash[:discoverable_authentication]).to be_nil
      end
    end
  end

  describe "POST /users/passkeys/add_callback" do
    # @lat: [[malformed-passkey-credential-tests#Web passkey addition]]
    MalformedWebauthnCredentials::REGISTRATION_CORRUPTIONS.each do |corruption, corrupt|
      it "answers success false with the verification-failed message for #{corruption}" do
        client = MalformedWebauthnCredentials.client
        challenge = MalformedWebauthnCredentials.challenge
        account = create(:user, :registered, phone: MalformedWebauthnCredentials::PHONE)
        sign_in(account)
        session_hash[:add_passkey_verified_at] = Time.current.to_i
        session_hash[:add_passkey_registration] = {"challenge" => challenge}
        credential = corrupt.call(MalformedWebauthnCredentials.registration(client, challenge))

        expect {
          post add_callback_users_passkeys_path, params: {publicKeyCredential: credential, passkey_label: "iPad"}, as: :json
        }.not_to(change { account.passkeys.count })

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({"success" => false, "message" => MalformedWebauthnCredentials::WEB_REJECTION_MESSAGE})
        expect(session_hash[:add_passkey_registration]).to be_nil
      end
    end
  end

  describe "POST /api/v1/registrations/callback" do
    # @lat: [[malformed-passkey-credential-tests#Mobile enrollment]]
    MalformedWebauthnCredentials::REGISTRATION_CORRUPTIONS.each do |corruption, corrupt|
      it "answers 401 invalid_credentials for #{corruption}" do
        client = MalformedWebauthnCredentials.client
        challenge = MalformedWebauthnCredentials.challenge
        phone = MalformedWebauthnCredentials::PHONE
        token = SmsVerificationToken.issue!(phone)
        Rails.cache.write(
          "webauthn:challenge:malformed-registration",
          {challenge: challenge, phone: phone, sms_verified_token: token, webauthn_id: WebAuthn.generate_user_id},
          expires_in: 5.minutes
        )
        credential = corrupt.call(MalformedWebauthnCredentials.registration(client, challenge))

        expect {
          post "/api/v1/registrations/callback",
            params: {registration: {challenge_id: "malformed-registration", credential: credential, platform: "ios"}},
            as: :json
        }.not_to(change { [User.count, Passkey.count, ApiKey.count] })

        expect(response).to have_http_status(:unauthorized)
        expect(json_body[:error]).to eq({code: "invalid_credentials", message: "Passkey registration failed"})
        expect(Rails.cache.read("webauthn:challenge:malformed-registration")).to be_nil
        expect(SmsVerificationToken.peek(token)).to be_present
      end
    end
  end

  describe "POST /api/v1/sessions/callback" do
    # @lat: [[malformed-passkey-credential-tests#Mobile sign-in]]
    MalformedWebauthnCredentials::ASSERTION_CORRUPTIONS.each do |corruption, corrupt|
      it "answers 401 invalid_credentials for #{corruption}" do
        client = MalformedWebauthnCredentials.client
        challenge = MalformedWebauthnCredentials.challenge
        MalformedWebauthnCredentials.enroll_user(client)
        Rails.cache.write(
          "webauthn:challenge:malformed-session",
          {challenge: challenge, phone: MalformedWebauthnCredentials::PHONE},
          expires_in: 5.minutes
        )
        credential = corrupt.call(MalformedWebauthnCredentials.assertion(client, challenge))

        expect {
          post "/api/v1/sessions/callback",
            params: {session: {challenge_id: "malformed-session", credential: credential, platform: "ios"}},
            as: :json
        }.not_to change(ApiKey, :count)

        expect(response).to have_http_status(:unauthorized)
        expect(json_body[:error]).to eq({code: "invalid_credentials", message: "Passkey verification failed"})
        expect(Rails.cache.read("webauthn:challenge:malformed-session")).to be_nil
      end
    end
  end

  describe "POST /api/v1/passkeys/callback" do
    # @lat: [[malformed-passkey-credential-tests#Mobile passkey addition]]
    MalformedWebauthnCredentials::REGISTRATION_CORRUPTIONS.each do |corruption, corrupt|
      it "answers 401 invalid_credentials for #{corruption}" do
        client = MalformedWebauthnCredentials.client
        challenge = MalformedWebauthnCredentials.challenge
        phone = MalformedWebauthnCredentials::PHONE
        account = create(:user, :registered, phone: phone)
        token = SmsVerificationToken.issue!(phone)
        Rails.cache.write(
          "webauthn:challenge:malformed-passkey",
          {challenge: challenge, user_id: account.id, phone: phone, sms_verified_token: token, label: "iPad"},
          expires_in: 5.minutes
        )
        credential = corrupt.call(MalformedWebauthnCredentials.registration(client, challenge))
        headers = authenticate_as(account)

        expect {
          post "/api/v1/passkeys/callback",
            params: {passkey: {challenge_id: "malformed-passkey", credential: credential}},
            headers: headers,
            as: :json
        }.not_to(change { account.passkeys.count })

        expect(response).to have_http_status(:unauthorized)
        expect(json_body[:error]).to eq({code: "invalid_credentials", message: "Passkey verification failed"})
        expect(Rails.cache.read("webauthn:challenge:malformed-passkey")).to be_nil
        expect(SmsVerificationToken.peek(token)).to be_present
      end
    end
  end
end
