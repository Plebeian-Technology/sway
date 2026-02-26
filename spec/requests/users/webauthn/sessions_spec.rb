require "rails_helper"

RSpec.describe "Users::Webauthn::Sessions", type: :request do
  include_context "SessionDouble"
  include_context "WebAuthnDouble"
  include_context "TwilioDouble"

  describe "POST /users/webauthn/sessions" do
    let(:phone) { "4105553000" }

    around do |example|
      previous = ENV["SKIP_PHONE_VERIFICATION"]
      ENV.delete("SKIP_PHONE_VERIFICATION")
      example.run
    ensure
      previous.nil? ? ENV.delete("SKIP_PHONE_VERIFICATION") : ENV["SKIP_PHONE_VERIFICATION"] = previous
    end

    context "when phone is invalid" do
      it "redirects when phone is blank" do
        post users_webauthn_sessions_path, params: { phone: "" }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(root_path)
      end

      it "redirects when phone is 9 digits" do
        post users_webauthn_sessions_path, params: { phone: "410555300" }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(root_path)
      end

      it "redirects when phone is 11 digits" do
        post users_webauthn_sessions_path, params: { phone: "14105553000" }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(root_path)
      end
    end

    context "when user has passkeys" do
      let!(:user) { create(:user, phone: phone, is_registration_complete: true) }
      let!(:passkey) { create(:passkey, user: user, external_id: fake_credential_id) }

      it "returns authentication options" do
        post users_webauthn_sessions_path, params: { phone: phone }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["challenge"]).to eq(fake_challenge)
      end

      it "stores challenge and phone in current_authentication" do
        post users_webauthn_sessions_path, params: { phone: phone }

        expect(session_hash[:current_authentication]).to eq(
          {
            challenge: fake_challenge,
            phone: phone,
          },
        )
      end
    end

    context "when user has no passkeys" do
      before do
        create(:user, phone: phone)
      end

      context "when SKIP_PHONE_VERIFICATION is enabled" do
        around do |example|
          previous = ENV["SKIP_PHONE_VERIFICATION"]
          ENV["SKIP_PHONE_VERIFICATION"] = "1"
          example.run
        ensure
          previous.nil? ? ENV.delete("SKIP_PHONE_VERIFICATION") : ENV["SKIP_PHONE_VERIFICATION"] = previous
        end

        it "stores phone in session and returns success" do
          post users_webauthn_sessions_path, params: { phone: phone }

          expect(response).to have_http_status(:accepted)
          expect(response.parsed_body).to eq({ "success" => true })
          expect(session_hash[:phone]).to eq(phone)
        end
      end

      context "when SKIP_PHONE_VERIFICATION is disabled" do
        it "sends Twilio verification and returns success" do
          post users_webauthn_sessions_path, params: { phone: phone }

          expect(response).to have_http_status(:accepted)
          expect(response.parsed_body).to eq({ "success" => true })
          expect(session_hash[:phone]).to eq(phone)
        end

        it "returns false when Twilio fails" do
          allow_any_instance_of(Users::Webauthn::SessionsController).to receive(
            :send_phone_verification,
          ).and_return(false)

          post users_webauthn_sessions_path, params: { phone: phone }

          expect(response).to have_http_status(:accepted)
          expect(response.parsed_body).to eq({ "success" => false })
        end
      end
    end

    context "when no user exists and phone is present" do
      it "starts phone verification flow" do
        post users_webauthn_sessions_path, params: { phone: phone }

        expect(response).to have_http_status(:accepted)
        expect(response.parsed_body).to eq({ "success" => true })
        expect(session_hash[:phone]).to eq(phone)
      end
    end
  end

  describe "POST /users/webauthn/sessions/callback" do
    let(:phone) { "4105554000" }
    let(:callback_params) do
      {
        publicKeyCredential: {
          id: fake_credential_id,
          rawId: Base64.strict_encode64(fake_credential_id),
        },
      }
    end

    before do
      session_hash[:current_authentication] = {
        "challenge" => fake_challenge,
        "phone" => phone,
      }
    end

    context "when authentication succeeds" do
      let!(:user) do
        create(:user, phone: phone).tap do |created_user|
          created_user.update!(
            is_registration_complete: registration_complete,
            registration_status: registration_complete ? "completed" : "pending",
          )
        end
      end
      let!(:passkey) { create(:passkey, user: user, external_id: fake_credential_id, sign_count: 0) }
      let(:registration_complete) { true }

      it "signs in the user" do
        post callback_users_webauthn_sessions_path, params: callback_params

        expect(session_hash[:user_id]).to eq(user.id)
      end

      it "sets verified_phone" do
        post callback_users_webauthn_sessions_path, params: callback_params

        expect(session_hash[:verified_phone]).to eq(phone)
      end

      it "updates passkey sign_count" do
        post callback_users_webauthn_sessions_path, params: callback_params

        expect(passkey.reload.sign_count).to eq(42)
      end

      it "routes to legislators when registration is complete" do
        post callback_users_webauthn_sessions_path, params: callback_params

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["route"]).to eq(legislators_path)
      end

      it "cleans current_authentication from session" do
        post callback_users_webauthn_sessions_path, params: callback_params

        expect(session_hash[:current_authentication]).to be_nil
      end

      context "when registration is incomplete" do
        let(:registration_complete) { false }

        it "routes to registration" do
          post callback_users_webauthn_sessions_path, params: callback_params

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body["route"]).to eq(sway_registration_index_path)
        end
      end
    end

    it "raises when user is not found" do
      expect do
        post callback_users_webauthn_sessions_path, params: callback_params
      end.to raise_error(RuntimeError, "user #{phone} never initiated sign up")

      expect(session_hash[:current_authentication]).to eq(
        {
          "challenge" => fake_challenge,
          "phone" => phone,
        },
      )
    end

    it "returns 422 on WebAuthn error and cleans session" do
      create(:user, phone: phone)
      create(:passkey, user: User.find_by(phone: phone), external_id: fake_credential_id)

      allow_any_instance_of(WebAuthn::RelyingParty).to receive(
        :verify_authentication,
      ).and_raise(WebAuthn::Error, "bad assertion")

      post callback_users_webauthn_sessions_path, params: callback_params

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["message"]).to eq(
        "Verification failed: bad assertion",
      )
      expect(session_hash[:current_authentication]).to be_nil
    end
  end

  describe "DELETE /users/webauthn/sessions/:id" do
    it "clears session on sign out" do
      user = create(:user)
      session_hash[:user_id] = user.id

      delete users_webauthn_session_path("1")

      expect(session_hash[:user_id]).to be_nil
    end
  end
end
