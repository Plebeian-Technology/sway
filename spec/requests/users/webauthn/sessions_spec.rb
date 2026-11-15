require "rails_helper"

RSpec.describe "Users::Webauthn::Sessions", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  include_context "SessionDouble"
  include_context "WebAuthnDouble"
  include_context "TwilioDouble"

  describe "POST /users/webauthn/sessions" do
    let(:phone) { "4105553000" }

    around do |example|
      with_app_config(:dev_login, skip_phone_verification: false) { example.run }
    end

    context "when phone is invalid" do
      it "redirects when phone is blank" do
        post users_webauthn_sessions_path, params: {phone: ""}

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(root_path)
      end

      it "redirects when phone is 9 digits" do
        post users_webauthn_sessions_path, params: {phone: "410555300"}

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(root_path)
      end

      it "redirects when phone is 11 digits and does not start with country code 1" do
        post users_webauthn_sessions_path, params: {phone: "24105553000"}

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(root_path)
      end

      it "answers the phone error as JSON and sends no SMS for a number no US phone can have" do
        post users_webauthn_sessions_path, params: {phone: "1234567890"}

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({"flow" => "sms", "success" => false, "error" => "Enter a valid US phone number."})
        expect(twilio_verifications_double).not_to have_received(:create)
      end

      it "still answers the passkey flow for a stored phone no US phone can have" do
        user = create(:user, :registered, phone: "1234567890")
        create(:passkey, user: user, external_id: fake_credential_id)

        post users_webauthn_sessions_path, params: {phone: "1234567890"}

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["flow"]).to eq("passkey")
      end

      it "accepts an 11-digit input that starts with country code 1 by normalizing to 10 digits" do
        user = create(:user, :registered, phone: "4105553000")
        create(:passkey, user: user, external_id: fake_credential_id)

        post users_webauthn_sessions_path, params: {phone: "14105553000"}

        expect(response).to have_http_status(:ok)
      end
    end

    context "when user has passkeys" do
      let!(:user) do
        create(:user, :registered, phone: phone)
      end
      let!(:passkey) do
        create(:passkey, user: user, external_id: fake_credential_id)
      end

      it "passes all passkeys as allow_credentials" do
        second_passkey =
          create(:passkey, user: user, external_id: "second-credential")

        expect_any_instance_of(WebAuthn::RelyingParty).to receive(
          :options_for_authentication
        ).with(
          hash_including(
            allow_credentials:
              match_array(
                [
                  {id: passkey.external_id, type: "public-key"},
                  {id: second_passkey.external_id, type: "public-key"}
                ]
              )
          )
        ).and_return(authentication_options_double)

        post users_webauthn_sessions_path, params: {phone: phone}
      end

      it "returns authentication options under the passkey-flow envelope" do
        post users_webauthn_sessions_path, params: {phone: phone}

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["flow"]).to eq("passkey")
        expect(response.parsed_body.dig("options", "challenge")).to eq(fake_challenge)
      end

      it "stores challenge and phone in current_authentication" do
        post users_webauthn_sessions_path, params: {phone: phone}

        expect(session_hash[:current_authentication]).to eq(
          {challenge: fake_challenge, phone: phone}
        )
      end
    end

    context "when user has no passkeys" do
      before { create(:user, phone: phone) }

      context "when the skip switch is on" do
        around do |example|
          with_app_config(:dev_login, skip_phone_verification: true) { example.run }
        end

        it "stores phone in session and returns success" do
          post users_webauthn_sessions_path, params: {phone: phone}

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq({"flow" => "sms", "success" => true})
          expect(session_hash[:phone]).to eq(phone)
        end
      end

      context "when the skip switch is off" do
        it "sends Twilio verification and returns success" do
          post users_webauthn_sessions_path, params: {phone: phone}

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq({"flow" => "sms", "success" => true})
          expect(session_hash[:phone]).to eq(phone)
        end

        it "returns false when Twilio fails" do
          allow_any_instance_of(Users::Webauthn::SessionsController).to receive(
            :send_phone_verification
          ).and_return(false)

          post users_webauthn_sessions_path, params: {phone: phone}

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq({"flow" => "sms", "success" => false})
        end
      end
    end

    context "when no user exists and phone is present" do
      it "starts phone verification flow" do
        post users_webauthn_sessions_path, params: {phone: phone}

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({"flow" => "sms", "success" => true})
        expect(session_hash[:phone]).to eq(phone)
      end
    end

    context "when this session already confirmed the phone" do
      it "answers the enroll flow without a second SMS and lets enrollment start" do
        post users_webauthn_sessions_path, params: {phone: phone}
        patch phone_verification_path("0"), params: {phone_verification: {code: "123456"}}
        expect(session_hash[:verified_phone]).to eq(phone)
        session_hash[:phone] = "4105553999"

        post users_webauthn_sessions_path, params: {phone: phone}

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({"flow" => "enroll"})
        expect(twilio_verifications_double).to have_received(:create).once
        expect(session_hash[:phone]).to eq(phone)

        post users_webauthn_registration_index_path

        expect(response.parsed_body["challenge"]).to eq(fake_challenge)
      end

      # @lat: [[phone-verification-rate-limits#Why the sign-in challenge throttles two ways]]
      it "does not count resumed enrollments against the phone and IP sign-in limit" do
        with_rate_limit_enabled(:sign_in) do
          post users_webauthn_sessions_path, params: {phone: phone}
          patch phone_verification_path("0"), params: {phone_verification: {code: "123456"}}
          expect(session_hash[:verified_phone]).to eq(phone)

          8.times { post users_webauthn_sessions_path, params: {phone: phone} }

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq({"flow" => "enroll"})
        end
      end

      it "still counts unconfirmed sends against the phone and IP sign-in limit" do
        with_rate_limit_enabled(:sign_in) do
          6.times { post users_webauthn_sessions_path, params: {phone: phone}, as: :json }

          expect(response).to have_http_status(:too_many_requests)
          expect(response.headers["Retry-After"]).to eq("300")
        end
      end

      it "sends a new SMS once the confirmation is older than the window" do
        post users_webauthn_sessions_path, params: {phone: phone}
        patch phone_verification_path("0"), params: {phone_verification: {code: "123456"}}
        expect(session_hash[:verified_phone]).to eq(phone)

        travel(VerifiedPhoneSession::VERIFIED_PHONE_WINDOW + 1.minute) do
          post users_webauthn_sessions_path, params: {phone: phone}
        end

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({"flow" => "sms", "success" => true})
        expect(twilio_verifications_double).to have_received(:create).twice
      end

      it "sends an SMS when the session confirmed a different phone" do
        session_hash[:verified_phone] = "4105553999"

        post users_webauthn_sessions_path, params: {phone: phone}

        expect(response.parsed_body).to eq({"flow" => "sms", "success" => true})
        expect(twilio_verifications_double).to have_received(:create).once
      end

      it "sends an SMS when the session confirmed no phone" do
        post users_webauthn_sessions_path, params: {phone: phone}

        expect(response.parsed_body).to eq({"flow" => "sms", "success" => true})
        expect(twilio_verifications_double).to have_received(:create).once
      end
    end

    # @lat: [[identity-and-access#The sign-in challenge says which ceremony to run]]
    context "account enumeration" do
      it "answers 200 with a flow envelope for passkey, passkey-less, and unknown phones alike" do
        with_passkey = create(:user, :registered, phone: "4105553111")
        create(:passkey, user: with_passkey, external_id: fake_credential_id)
        create(:user, phone: "4105553222") # registered, no passkey enrolled

        results = %w[4105553111 4105553222 4105553333].map do |probe|
          post users_webauthn_sessions_path, params: {phone: probe}
          [response.status, response.parsed_body.key?("flow")]
        end

        expect(results).to all(eq([200, true]))
      end
    end
  end

  describe "POST /users/webauthn/sessions/callback" do
    let(:phone) { "4105554000" }
    let(:callback_params) do
      {
        publicKeyCredential: {
          id: fake_credential_id,
          rawId: Base64.strict_encode64(fake_credential_id)
        }
      }
    end

    before do
      session_hash[:current_authentication] = {
        "challenge" => fake_challenge,
        "phone" => phone
      }
    end

    context "when authentication succeeds" do
      let!(:user) do
        create(:user, phone: phone).tap do |created_user|
          if registration_complete
            create(:user_legislator, user: created_user)
            created_user.complete!
          end
        end
      end
      let!(:passkey) do
        create(
          :passkey,
          user: user,
          external_id: fake_credential_id,
          sign_count: 0
        )
      end
      let(:registration_complete) { true }

      it "signs in the user" do
        post callback_users_webauthn_sessions_path, params: callback_params

        expect(session_hash[:user_id]).to eq(user.id)
        expect(session_hash[:inertia_clear_history]).to be true
      end

      it "resets old session data before writing auth state" do
        session_hash[:attacker_session] = "stale"

        post callback_users_webauthn_sessions_path, params: callback_params

        expect(session_hash[:attacker_session]).to be_nil
        expect(session_hash[:user_id]).to eq(user.id)
        expect(session_hash[:inertia_clear_history]).to be true
        expect(session_hash[:verified_phone]).to eq(phone)
      end

      it "writes a refresh token cookie on sign in" do
        post callback_users_webauthn_sessions_path, params: callback_params

        expect(cookies_hash[:refresh_token]).to eq({value: "refresh-token"})
      end

      it "sets verified_phone" do
        post callback_users_webauthn_sessions_path, params: callback_params

        expect(session_hash[:verified_phone]).to eq(phone)
      end

      it "updates passkey sign_count" do
        post callback_users_webauthn_sessions_path, params: callback_params

        expect(passkey.reload.sign_count).to eq(42)
      end

      it "updates passkey last_used_at" do
        expect {
          post callback_users_webauthn_sessions_path, params: callback_params
        }.to change { passkey.reload.last_used_at }.from(nil)
      end

      it "redirects to feed when registration is complete" do
        post callback_users_webauthn_sessions_path, params: callback_params

        expect(response).to redirect_to(feed_path)
      end

      # @lat: [[low-friction-voting#Reconciliation on registration and sign-in]]
      it "reconciles pending vote and redirects to bill when a pending vote cookie exists" do
        bill = create(:bill)
        post provisional_votes_path, params: {bill_id: bill.id, support: "FOR"}

        expect {
          post callback_users_webauthn_sessions_path, params: callback_params
        }.to change(UserVote, :count).by(1)

        expect(response).to redirect_to(bill_path(bill))
        expect(response.cookies["sway_pending_vote"]).to be_nil
        expect(UserVote.find_by(user: user, bill: bill).support).to eq("FOR")
      end

      it "cleans current_authentication from session" do
        post callback_users_webauthn_sessions_path, params: callback_params

        expect(session_hash[:current_authentication]).to be_nil
      end

      # An older user row that fails validation when we bump its sign-in counter
      # must still be able to sign in, so the code uses `save` and not `save!`.
      # The failed save is logged rather than thrown away.
      it "still signs in and logs when the sign-in counter save fails" do
        allow(SwayLogging).to receive(:info)
        allow_any_instance_of(User).to receive(:save).and_return(false)

        post callback_users_webauthn_sessions_path, params: callback_params

        expect(session_hash[:user_id]).to eq(user.id)
        expect(session_hash[:inertia_clear_history]).to be true
        expect(SwayLogging).to have_received(:info).with(
          "sign_in.counter_update_failed",
          hash_including(:user_id, :errors)
        )
      end

      context "when registration is incomplete" do
        let(:registration_complete) { false }

        it "redirects to registration" do
          post callback_users_webauthn_sessions_path, params: callback_params

          expect(response).to redirect_to(sway_registration_index_path)
        end
      end

      context "when passkey is found by base64 raw_id fallback" do
        let(:fallback_external_id) do
          Base64.strict_encode64(Base64.strict_encode64(fake_credential_id))
        end
        let!(:passkey) do
          create(
            :passkey,
            user: user,
            external_id: fallback_external_id,
            sign_count: 0
          )
        end

        it "updates the fallback-matched passkey" do
          post callback_users_webauthn_sessions_path, params: callback_params

          expect(passkey.reload.sign_count).to eq(42)
        end
      end
    end

    it "redirects to root with alert when user is not found" do
      post callback_users_webauthn_sessions_path, params: callback_params

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("User not found for authentication.")
      expect(session_hash[:current_authentication]).to be_nil
    end

    it "redirects to root with alert when current_authentication is missing" do
      session_hash.delete(:current_authentication)

      post callback_users_webauthn_sessions_path, params: callback_params

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(
        "Authentication session expired. Please try again."
      )
      expect(session_hash[:current_authentication]).to be_nil
    end

    it "redirects to root with alert on WebAuthn error and cleans session" do
      create(:user, phone: phone)
      create(
        :passkey,
        user: User.find_by(phone: phone),
        external_id: fake_credential_id
      )

      allow_any_instance_of(WebAuthn::RelyingParty).to receive(
        :verify_authentication
      ).and_raise(WebAuthn::Error, "bad assertion")

      post callback_users_webauthn_sessions_path, params: callback_params

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(Users::Webauthn::SessionsController::PASSKEY_VERIFICATION_FAILED_MESSAGE)
      expect(flash[:alert]).not_to include("bad assertion")
      expect(session_hash[:current_authentication]).to be_nil
    end

    it "redirects to root with alert when publicKeyCredential payload is missing" do
      create(:user, phone: phone)

      post callback_users_webauthn_sessions_path, params: {}

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(
        "Invalid authentication payload: missing publicKeyCredential"
      )
      expect(session_hash[:current_authentication]).to be_nil
    end

    it "redirects to root with alert when verified credential no longer maps to a passkey" do
      create(:user, phone: phone)
      create(
        :passkey,
        user: User.find_by(phone: phone),
        external_id: "different-id"
      )

      post callback_users_webauthn_sessions_path, params: callback_params

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Passkey not found for this account.")
      expect(session_hash[:current_authentication]).to be_nil
    end
  end

  # @lat: [[identity-and-access#The sign-in challenge says which ceremony to run]]
  describe "POST /users/webauthn/sessions/discoverable_challenge" do
    it "returns passkey-flow options and stores the challenge, taking no phone" do
      post discoverable_challenge_users_webauthn_sessions_path

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["flow"]).to eq("passkey")
      expect(response.parsed_body.dig("options", "challenge")).to eq(fake_challenge)
      expect(session_hash[:discoverable_authentication]).to eq({challenge: fake_challenge})
    end
  end

  describe "POST /users/webauthn/sessions/discoverable_callback" do
    let(:phone) { "4105557000" }
    let(:callback_params) do
      {
        publicKeyCredential: {
          id: fake_credential_id,
          rawId: Base64.strict_encode64(fake_credential_id)
        }
      }
    end

    before do
      session_hash[:discoverable_authentication] = {"challenge" => fake_challenge}
    end

    it "resolves the user from the credential and signs in" do
      user = create(:user, phone: phone)
      complete_registration_with_active_link(user)
      create(:passkey, user: user, external_id: fake_credential_id)

      post discoverable_callback_users_webauthn_sessions_path, params: callback_params

      expect(session_hash[:user_id]).to eq(user.id)
      expect(session_hash[:inertia_clear_history]).to be true
      expect(session_hash[:verified_phone]).to eq(phone)
      expect(response).to redirect_to(feed_path)
      expect(session_hash[:discoverable_authentication]).to be_nil
    end

    it "sends a user with a passkey and no address to the registration form" do
      user = create(:user, phone: phone)
      create(:passkey, user: user, external_id: fake_credential_id)

      post discoverable_callback_users_webauthn_sessions_path, params: callback_params

      expect(response).to redirect_to(sway_registration_index_path)
      expect(session_hash[:user_id]).to eq(user.id)
      expect(session_hash[:verified_phone]).to eq(phone)
      expect(session_hash[:discoverable_authentication]).to be_nil
    end

    it "redirects to root when the discoverable challenge is missing" do
      session_hash.delete(:discoverable_authentication)

      post discoverable_callback_users_webauthn_sessions_path, params: callback_params

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Authentication session expired. Please try again.")
    end

    # @lat: [[identity-and-access#Identity and access#The sign-in challenge says which ceremony to run#A missing stored passkey must stop verification before key access]]
    it "redirects to root when the credential maps to no passkey" do
      create(:user, phone: phone).tap do |u|
        create(:passkey, user: u, external_id: "some-other-credential")
      end

      post discoverable_callback_users_webauthn_sessions_path, params: callback_params

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Passkey not recognized. Please try again.")
      expect(session_hash[:user_id]).to be_nil
      expect(session_hash[:discoverable_authentication]).to be_nil
    end
  end

  describe "DELETE /users/webauthn/sessions/:id" do
    it "clears session and deletes refresh tokens on sign out" do
      user = create(:user)
      rt = RefreshToken.create!(
        user: user,
        token: "cookie-rt-123",
        expires_at: 1.day.from_now,
        ip_address: "127.0.0.1",
        user_agent: "RSpec"
      )
      cookies_hash[:refresh_token] = rt.token
      session_hash[:user_id] = user.id

      delete users_webauthn_session_path("1")

      expect(session_hash[:user_id]).to be_nil
      expect(RefreshToken.find_by(id: rt.id)).to be_nil
    end

    # @lat: [[client-caches-and-identity#Why sign-out does not clear them by itself]]
    it "signals Inertia to clear browser history on sign out" do
      user = create(:user)
      session_hash[:user_id] = user.id

      delete users_webauthn_session_path("1")

      expect(session_hash[:inertia_clear_history]).to be true
    end
  end

  describe "an unexpected error" do
    before do
      allow(User).to receive(:find_by).and_raise(RuntimeError, "boom")
      allow(Sentry).to receive(:capture_exception)
    end

    it "answers 503 onboarding_unavailable to the JSON sign-in start and reports the error" do
      post users_webauthn_sessions_path, params: {phone: "4105553000"}, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("error", "code")).to eq("onboarding_unavailable")
      expect(Sentry).to have_received(:capture_exception).with(an_instance_of(RuntimeError), any_args).once
    end
  end
end
