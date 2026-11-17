# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users::Passkeys", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /users/passkeys (cookie / Inertia)" do
    it "renders the PasskeyManagement Inertia page for the authenticated user" do
      _, user = setup
      create(:passkey, user: user, label: "iPhone 15", last_used_at: 2.days.ago)
      create(:passkey, user: user, label: "MacBook Air", last_used_at: nil)

      get "/users/passkeys"

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::PASSKEY_MANAGEMENT)
      expect(inertia.props.keys).to include("passkeys")
    end

    it "renders only current_user's passkeys (T-37-05-01 cross-user scoping)" do
      _, user = setup
      mine = create(:passkey, user: user, label: "Mine")
      other = create(:user, :registered)
      theirs = create(:passkey, user: other, label: "Theirs")

      get "/users/passkeys", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      ids = body[:passkeys].pluck(:id)
      expect(ids).to include(mine.id)
      expect(ids).not_to include(theirs.id)
    end
  end

  describe "GET /users/passkeys (bearer / JSON)" do
    let(:user) do
      u = create(:user)
      complete_registration_with_active_link(u)
      u
    end

    it "returns { passkeys: [...] } JSON for the authenticated bearer caller" do
      headers = authenticate_as(user)
      # Give the passkeys AAGUIDs — the ids that say which authenticator model
      # made them — so the :device field gets used: one the app recognizes, one
      # it does not.
      create(:passkey, user: user, label: "iPhone 15",
        aaguid: "dd4ec289-e01d-41c9-bb89-70fa845d4bf2",
        created_at: Time.zone.parse("2026-01-15T00:00:00Z"),
        last_used_at: Time.zone.parse("2026-04-20T00:00:00Z"))
      create(:passkey, user: user, label: "MacBook Air",
        aaguid: nil,
        created_at: Time.zone.parse("2026-02-01T00:00:00Z"),
        last_used_at: nil)

      get "/users/passkeys", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body[:passkeys]).to be_an(Array)
      expect(body[:passkeys].length).to eq(2)
      sample = body[:passkeys].first
      # :device is part of the payload now.
      expect(sample.keys).to contain_exactly(:id, :label, :created_at, :last_used_at, :device)
      # Newest first by created_at, so the MacBook (February) comes before the iPhone (January).
      expect(body[:passkeys].pluck(:label)).to eq(["MacBook Air", "iPhone 15"])
      # Resolved name for the known AAGUID; nil for the missing one.
      by_label = body[:passkeys].each_with_object(
        {} #: Hash[untyped, untyped]
      ) { |p, h| h[p[:label]] = p[:device] }
      expect(by_label["iPhone 15"]).to eq("iCloud Keychain (Managed)")
      expect(by_label["MacBook Air"]).to be_nil
    end

    it "scopes to current_user — does not leak other users' passkeys" do
      headers = authenticate_as(user)
      mine = create(:passkey, user: user, label: "Mine")
      other = create(:user)
      complete_registration_with_active_link(other)
      theirs = create(:passkey, user: other, label: "Theirs")

      get "/users/passkeys", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = json_body[:passkeys].pluck(:id)
      expect(ids).to include(mine.id)
      expect(ids).not_to include(theirs.id)
    end

    it "returns 401 unauthorized without bearer or session" do
      get "/users/passkeys", as: :json

      # Either 401 JSON (bearer rejected) or redirect to sign-in (cookie path).
      expect([302, 401, 403]).to include(response.status)
    end
  end

  # Adding another passkey on purpose: a signed-in user registers an extra
  # passkey after proving their phone again by SMS.
  describe "add a passkey" do
    include_context "WebAuthnDouble"
    include_context "TwilioDouble"

    around do |example|
      with_app_config(:dev_login, skip_phone_verification: false) { example.run }
    end

    it "verify_phone sends an SMS to the current user and returns success" do
      setup

      post verify_phone_users_passkeys_path

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({"success" => true})
    end

    it "confirm_phone opens the add-a-passkey window on an approved code" do
      setup

      post confirm_phone_users_passkeys_path, params: {code: "123456"}

      expect(response.parsed_body).to eq({"success" => true})
      expect(session_hash[:add_passkey_verified_at]).to be_present
    end

    context "when the SMS code is not approved" do
      let(:twilio_verification_status) { "pending" }

      it "confirm_phone returns success:false and does NOT open the window" do
        setup

        post confirm_phone_users_passkeys_path, params: {code: "123456"}

        expect(response.parsed_body).to eq({"success" => false})
        expect(session_hash[:add_passkey_verified_at]).to be_nil
      end
    end

    it "confirm_phone returns success:false when Twilio cannot be reached" do
      setup
      allow(twilio_verification_checks_double).to receive(:create).and_raise(
        Twilio::REST::TwilioError.new("execution expired")
      )

      post confirm_phone_users_passkeys_path, params: {code: "123456"}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({"success" => false})
      expect(session_hash[:add_passkey_verified_at]).to be_nil
    end

    it "verify_phone returns success:false when Twilio cannot be reached" do
      setup
      allow(twilio_verifications_double).to receive(:create).and_raise(
        Twilio::REST::TwilioError.new("execution expired")
      )

      post verify_phone_users_passkeys_path

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({"success" => false})
    end

    context "when the Twilio Verify service id is not set" do
      around do |example|
        with_env(
          "TWILIO_ACCOUNT_SID" => "AC00000000000000000000000000000000",
          "TWILIO_AUTH_TOKEN" => "test-auth-token",
          "TWILIO_VERIFY_SERVICE_SID" => nil
        ) { example.run }
      end

      before do
        allow(Twilio::REST::Client).to receive(:new).and_call_original
        allow(Sentry).to receive(:capture_exception)
      end

      it "verify_phone and confirm_phone answer success:false and report the missing setting" do
        setup

        post verify_phone_users_passkeys_path
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({"success" => false})

        post confirm_phone_users_passkeys_path, params: {code: "123456"}
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({"success" => false})
        expect(session_hash[:add_passkey_verified_at]).to be_nil

        expect(Sentry).to have_received(:capture_exception)
          .with(an_instance_of(Authentication::VerifyServiceNotConfiguredError)).twice
      end
    end

    it "add_options refuses to issue a challenge without a fresh phone confirmation" do
      setup

      post add_options_users_passkeys_path

      expect(response.parsed_body).to eq(
        {"success" => false, "message" => "Confirm your phone number first."}
      )
      expect(session_hash[:add_passkey_registration]).to be_nil
    end

    it "add_options issues discoverable registration options after confirmation" do
      setup
      post confirm_phone_users_passkeys_path, params: {code: "123456"}

      expect_any_instance_of(WebAuthn::RelyingParty).to receive(
        :options_for_registration
      ).with(
        hash_including(
          authenticator_selection:
            hash_including(resident_key: "preferred", user_verification: "required")
        )
      ).and_return(registration_options_double)

      post add_options_users_passkeys_path

      expect(response).to have_http_status(:ok)
      expect(session_hash.dig(:add_passkey_registration, :challenge)).to eq(fake_challenge)
    end

    it "add_callback persists a new passkey on the current account" do
      _, user = setup
      post confirm_phone_users_passkeys_path, params: {code: "123456"}
      session_hash[:add_passkey_registration] = {"challenge" => fake_challenge}

      expect {
        post add_callback_users_passkeys_path,
          params: {publicKeyCredential: {id: fake_credential_id}, passkey_label: "iPad"}
      }.to change { user.passkeys.count }.by(1)

      expect(response.parsed_body).to eq({"success" => true})
      expect(user.passkeys.order(:created_at).last.label).to eq("iPad")
      expect(session_hash[:add_passkey_verified_at]).to be_nil
    end

    it "add_callback rejects a duplicate device label" do
      _, user = setup
      create(:passkey, user: user, label: "iPad")
      post confirm_phone_users_passkeys_path, params: {code: "123456"}
      session_hash[:add_passkey_registration] = {"challenge" => fake_challenge}

      expect {
        post add_callback_users_passkeys_path,
          params: {publicKeyCredential: {id: fake_credential_id}, passkey_label: "iPad"}
      }.not_to change { user.passkeys.count }

      expect(response.parsed_body["success"]).to eq(false)
      expect(response.parsed_body["message"]).to match(/already been taken/i)
    end

    it "add_callback disambiguates default passkey labels when enrolling multiple unlabeled passkeys" do
      _, user = setup
      create(:passkey, user: user, label: "New passkey")
      post confirm_phone_users_passkeys_path, params: {code: "123456"}
      session_hash[:add_passkey_registration] = {"challenge" => fake_challenge}

      expect {
        post add_callback_users_passkeys_path,
          params: {publicKeyCredential: {id: fake_credential_id}}
      }.to change { user.passkeys.count }.by(1)

      expect(response.parsed_body).to eq({"success" => true})
      expect(user.passkeys.order(:created_at).last.label).to eq("New passkey 2")
    end

    it "add_callback answers the fixed message and reports a failed verification to Sentry as a warning by exception class only" do
      _, user = setup
      post confirm_phone_users_passkeys_path, params: {code: "123456"}
      session_hash[:add_passkey_registration] = {"challenge" => fake_challenge}
      allow(Sentry).to receive(:capture_message)
      allow_any_instance_of(WebAuthn::RelyingParty).to receive(
        :verify_registration
      ).and_raise(WebAuthn::Error, "bad attestation")

      expect {
        post add_callback_users_passkeys_path,
          params: {publicKeyCredential: {id: fake_credential_id}, passkey_label: "iPad"}
      }.not_to change { user.passkeys.count }

      expect(response.parsed_body).to eq(
        {"success" => false, "message" => Users::PasskeysController::ADD_PASSKEY_FAILED_MESSAGE}
      )
      expect(Sentry).to have_received(:capture_message).once do |message, **options|
        expect(message).to eq("passkeys.add.verification_failed")
        expect(options[:level]).to eq(:warning)
        expect(options[:tags]).to eq(exception_class: "WebAuthn::Error")
        expect(options[:fingerprint]).to eq(["passkeys.add.verification_failed", "WebAuthn::Error"])
        expect(options[:extra]).to eq(exception_class: "WebAuthn::Error")
        expect(options.to_s).not_to include("bad attestation")
        expect(options.to_s).not_to include(user.phone)
      end
    end

    it "add_callback refuses when the phone confirmation has expired" do
      setup
      session_hash[:add_passkey_registration] = {"challenge" => fake_challenge}
      # confirm_phone was never called, so no add_passkey_verified_at window is open.

      post add_callback_users_passkeys_path,
        params: {publicKeyCredential: {id: fake_credential_id}, passkey_label: "iPad"}

      expect(response.parsed_body).to eq(
        {"success" => false, "message" => "Add-a-passkey session expired. Please try again."}
      )
    end

    it "throttles verify_phone after 3 requests for the same phone and IP for the hour, then sends from another IP" do
      setup

      with_rate_limit_enabled(:phone_verify) do
        freeze_time do
          4.times do
            post verify_phone_users_passkeys_path, headers: {"REMOTE_ADDR" => "10.0.0.1"}, as: :json
            travel 61.seconds
          end

          expect(response).to have_http_status(:too_many_requests)
          expect(response.headers["Retry-After"]).to eq(1.hour.to_i.to_s)

          post verify_phone_users_passkeys_path, headers: {"REMOTE_ADDR" => "10.0.0.2"}, as: :json

          expect(response).to have_http_status(:ok)
        end
      end
    end

    context "when the send limit per phone applies" do
      before { setup }

      def code_send_request(ip:)
        post verify_phone_users_passkeys_path, headers: {"REMOTE_ADDR" => ip}, as: :json
      end

      let(:code_send_status) { :ok }

      include_examples "a code send limited per phone"
    end

    it "throttles confirm_phone after 5 requests for the same phone when phone_verify rate limiting is enabled" do
      setup

      with_rate_limit_enabled(:phone_verify) do
        6.times do |i|
          post confirm_phone_users_passkeys_path,
            params: {code: "123456"},
            headers: {"REMOTE_ADDR" => "10.0.1.#{i + 1}"},
            as: :json
        end

        expect(response).to have_http_status(:too_many_requests)
        expect(response.headers["Retry-After"]).to eq(1.hour.to_i.to_s)
      end
    end
  end

  describe "DELETE /users/passkeys/:id" do
    include_context "WebAuthnDouble"
    include_context "TwilioDouble"

    it "removes a passkey when phone confirmed" do
      _, user = setup
      passkey = create(:passkey, user: user)
      create(:passkey, user: user) # At least two

      post confirm_phone_users_passkeys_path, params: {code: "123456"}
      
      delete users_passkey_path(passkey)
      
      expect(response).to have_http_status(:ok)
      expect(user.passkeys.find_by(id: passkey.id)).to be_nil
      expect(session_hash[:add_passkey_verified_at]).to be_nil # Window cleared
    end

    it "refuses to remove the last passkey" do
      _, user = setup
      passkey = create(:passkey, user: user)
      # Only one passkey

      post confirm_phone_users_passkeys_path, params: {code: "123456"}
      
      delete users_passkey_path(passkey)
      
      expect(response).to have_http_status(:forbidden)
      expect(user.passkeys.find_by(id: passkey.id)).not_to be_nil
    end

    it "refuses to remove passkey without phone confirmation" do
      _, user = setup
      passkey = create(:passkey, user: user)
      create(:passkey, user: user)

      delete users_passkey_path(passkey)
      
      expect(response).to have_http_status(:forbidden)
      expect(user.passkeys.find_by(id: passkey.id)).not_to be_nil
    end

    it "refuses to remove another user's passkey" do
      _, user = setup
      other_user = create(:user)
      passkey = create(:passkey, user: other_user)
      
      post confirm_phone_users_passkeys_path, params: {code: "123456"}
      
      delete users_passkey_path(passkey)
      expect(response).to have_http_status(:not_found)
    end
  end
end

