require "rails_helper"

RSpec.describe "Users::Webauthn::Registration", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  include_context "SessionDouble"
  include_context "WebAuthnDouble"

  describe "POST /users/webauthn/registration" do
    let(:phone) { "4105551000" }

    context "when phone is verified" do
      before do
        session_hash[:phone] = phone
        session_hash[:verified_phone] = phone
        session_hash[:verified_phone_at] = Time.current.to_i
      end

      it "still issues options just inside the verification window" do
        travel(VerifiedPhoneSession::VERIFIED_PHONE_WINDOW - 1.minute) do
          post users_webauthn_registration_index_path
        end

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["challenge"]).to eq(fake_challenge)
      end

      it "returns the confirmation message once the verification is older than the window" do
        travel(VerifiedPhoneSession::VERIFIED_PHONE_WINDOW + 1.minute) do
          post users_webauthn_registration_index_path
        end

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq(
          {
            "success" => false,
            "message" => "Please confirm your phone number first."
          }
        )
        expect(session_hash[:current_registration]).to be_nil
      end

      it "returns the confirmation message when the verified phone carries no verification time" do
        session_hash.delete(:verified_phone_at)

        post users_webauthn_registration_index_path

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq(
          {
            "success" => false,
            "message" => "Please confirm your phone number first."
          }
        )
      end

      it "returns 422 when user attributes are invalid" do
        user_errors =
          instance_double(ActiveModel::Errors, full_messages: ["user invalid"])
        allow_any_instance_of(User).to receive(:valid?).and_return(false)
        allow_any_instance_of(User).to receive(:errors).and_return(user_errors)

        post users_webauthn_registration_index_path

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq({"errors" => ["user invalid"]})
        expect(session_hash[:current_registration]).to be_nil
      end

      it "returns registration options with challenge" do
        post users_webauthn_registration_index_path

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["challenge"]).to eq(fake_challenge)
      end

      it "stores challenge and user attributes including webauthn_id in session" do
        post users_webauthn_registration_index_path

        expect(session_hash.dig(:current_registration, :challenge)).to eq(
          fake_challenge
        )
        expect(
          session_hash.dig(:current_registration, :user_attributes)
        ).to include("phone" => phone, "webauthn_id" => be_present)
        expect(
          session_hash.dig(:current_registration, :user_attributes)
        ).not_to include("is_registration_complete", "registration_status")
      end

      # @lat: [[identity-and-access#Identity and access#The phone number is the account#First-passkey enrollment]]
      it "refuses an SMS-verified account with an existing passkey" do
        user = create(:user, phone: phone, is_phone_verified: false)
        create(:passkey, user: user)
        original_attributes = user.attributes
        session_hash[:current_registration] = {challenge: "stale"}
        expect_any_instance_of(WebAuthn::RelyingParty).not_to receive(:options_for_registration)

        expect do
          post users_webauthn_registration_index_path
        end.not_to(change { [User.count, Passkey.count] })

        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body["errors"]).to include(/Sign in with your passkey/)
        expect(response.parsed_body).not_to have_key("challenge")
        expect(user.reload.attributes).to eq(original_attributes)
        expect(session_hash[:user_id]).to be_nil
        expect(cookies_hash[:refresh_token]).to be_nil
        expect(session_hash[:current_registration]).to be_nil
      end

      it "allows first enrollment for an existing account without passkeys" do
        create(:user, phone: phone, is_phone_verified: true)

        post users_webauthn_registration_index_path

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["challenge"]).to eq(fake_challenge)
      end

      # @lat: [[identity-and-access#Identity and access#The phone number is the account#Enrollment credential metadata]]
      it "requests a discoverable (resident) credential" do
        expect_any_instance_of(WebAuthn::RelyingParty).to receive(
          :options_for_registration
        ).with(
          hash_including(
            authenticator_selection:
              hash_including(resident_key: "preferred", user_verification: "required")
          )
        ).and_return(registration_options_double)

        post users_webauthn_registration_index_path
      end
    end

    context "when phone is not verified" do
      before { session_hash[:phone] = phone }

      it "returns a confirmation message" do
        post users_webauthn_registration_index_path

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq(
          {
            "success" => false,
            "message" => "Please confirm your phone number first."
          }
        )
      end

      it "returns the confirmation message when no phone was verified in the session" do
        session_hash.delete(:phone)

        post users_webauthn_registration_index_path

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq(
          {
            "success" => false,
            "message" => "Please confirm your phone number first."
          }
        )
      end

      it "returns the confirmation message when the verified phone is not the submitted phone" do
        session_hash[:verified_phone] = "4105559999"

        post users_webauthn_registration_index_path

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq(
          {
            "success" => false,
            "message" => "Please confirm your phone number first."
          }
        )
      end
    end
  end

  describe "POST /users/webauthn/registration/callback" do
    let(:phone) { "4105552000" }
    let(:callback_params) do
      {
        id: fake_credential_id,
        rawId: Base64.strict_encode64(fake_credential_id),
        passkey_label: "MacBook"
      }
    end

    before do
      session_hash[:verified_phone] = phone
      session_hash[:verified_phone_at] = Time.current.to_i
      session_hash[:current_registration] = {
        "challenge" => fake_challenge,
        "user_attributes" => {
          "phone" => phone,
          "is_registration_complete" => false
        }
      }
    end

    it "redirects with the expired message and saves nothing once the verification is older than the window" do
      expect do
        travel(VerifiedPhoneSession::VERIFIED_PHONE_WINDOW + 1.minute) do
          post callback_users_webauthn_registration_index_path, params: callback_params
        end
      end.not_to(change { [User.count, Passkey.count] })

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Registration session expired. Please try again.")
      expect(session_hash[:current_registration]).to be_nil
    end

    it "redirects with the expired message when the verified phone carries no verification time" do
      session_hash.delete(:verified_phone_at)

      expect do
        post callback_users_webauthn_registration_index_path, params: callback_params
      end.not_to(change { [User.count, Passkey.count] })

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Registration session expired. Please try again.")
    end

    ["existing passkey", "first passkey added after options", "new account enrolled after options"].each do |scenario|
      it "refuses SMS-only completion with #{scenario}" do
        user = create(:user, phone: phone, is_phone_verified: true) unless scenario == "new account enrolled after options"
        unless scenario == "existing passkey"
          session_hash[:phone] = phone
          post users_webauthn_registration_index_path
          expect(response).to have_http_status(:ok)
          user ||= create(:user, phone: phone, is_phone_verified: true)
        end
        create(:passkey, user: user)
        original_attributes = user.attributes

        expect do
          post callback_users_webauthn_registration_index_path, params: callback_params
        end.not_to(change { [User.count, Passkey.count] })

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("Sign in with your passkey")
        expect(user.reload.attributes).to eq(original_attributes)
        expect(session_hash[:user_id]).to be_nil
        expect(cookies_hash[:refresh_token]).to be_nil
        expect(session_hash[:current_registration]).to be_nil
      end
    end

    it "creates a user" do
      expect do
        post callback_users_webauthn_registration_index_path,
          params: callback_params
      end.to change(User, :count).by(1)
    end

    it "creates a passkey with verified data" do
      post callback_users_webauthn_registration_index_path,
        params: callback_params

      passkey = Passkey.last!
      expect(passkey.external_id).to eq(fake_credential_id)
      expect(passkey.public_key).to eq(fake_public_key)
      expect(passkey.label).to eq("MacBook")
      expect(passkey.sign_count).to eq(0)
    end

    it "signs in the user" do
      post callback_users_webauthn_registration_index_path,
        params: callback_params

      expect(session_hash[:user_id]).to eq(User.find_by(phone: phone)&.id)
      expect(session_hash[:inertia_clear_history]).to be true
    end

    it "resets old session data before setting user_id" do
      session_hash[:attacker_session] = "stale"

      post callback_users_webauthn_registration_index_path,
        params: callback_params

      expect(session_hash[:attacker_session]).to be_nil
      expect(session_hash[:user_id]).to eq(User.find_by(phone: phone)&.id)
      expect(session_hash[:inertia_clear_history]).to be true
    end

    it "writes a refresh token cookie on sign in" do
      post callback_users_webauthn_registration_index_path,
        params: callback_params

      expect(cookies_hash[:refresh_token]).to eq({value: "refresh-token"})
    end

    it "redirects to the registration route" do
      post callback_users_webauthn_registration_index_path,
        params: callback_params

      expect(response).to redirect_to(sway_registration_index_path)
    end

    it "renders the new identity with cleared history on the first destination" do
      previous = create(:user)
      session_hash[:user_id] = previous.id
      session_hash[:auth_identity] = previous.created_at.to_i
      post callback_users_webauthn_registration_index_path, params: callback_params

      follow_redirect!(headers: {"X-Inertia" => "true", "X-Inertia-Version" => InertiaRails.configuration.version.to_s, "User-Agent" => "RSpec Browser"})

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["clearHistory"]).to be true
      expect(inertia).to render_component(Pages::REGISTRATION)
      expect(inertia).to have_props { |props| props.dig("user", "id") == User.find_by!(phone: phone).id }
      expect(inertia).not_to have_props { |props| props.dig("user", "id") == previous.id }
    end

    it "cleans up current_registration session data" do
      post callback_users_webauthn_registration_index_path,
        params: callback_params

      expect(session_hash[:current_registration]).to be_nil
    end

    it "updates existing user instead of creating duplicate" do
      user = create(:user, phone: phone, is_phone_verified: false)

      expect do
        post callback_users_webauthn_registration_index_path,
          params: callback_params
      end.not_to change(User, :count)

      expect(Passkey.where(user: user).count).to eq(1)
      expect(session_hash[:user_id]).to eq(user.id)
    end

    # @lat: [[identity-and-access#Identity and access#The phone number is the account#Enrollment attributes exclude admin privileges]]
    it "does not grant admin from session-carried attributes onto an existing user" do
      stub_const("User::ADMIN_PHONES", ["4109999999"])
      existing = create(:user, phone: phone)
      session_hash[:current_registration] = {
        "challenge" => fake_challenge,
        "user_attributes" => {
          "phone" => phone,
          "is_registration_complete" => false,
          "is_admin" => true
        }
      }

      post callback_users_webauthn_registration_index_path,
        params: callback_params

      expect(response).to have_http_status(:redirect)
      expect(existing.reload.is_sway_admin?).to be(false)
    end

    it "redirects to root with an alert when WebAuthn verification fails" do
      allow_any_instance_of(WebAuthn::RelyingParty).to receive(
        :verify_registration
      ).and_raise(WebAuthn::Error, "bad attestation")

      post callback_users_webauthn_registration_index_path,
        params: callback_params

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Verification failed: bad attestation")
      expect(session_hash[:current_registration]).to be_nil
    end

    it "does not persist user or passkey when WebAuthn verification fails" do
      allow_any_instance_of(WebAuthn::RelyingParty).to receive(
        :verify_registration
      ).and_raise(WebAuthn::Error, "bad attestation")

      expect do
        post callback_users_webauthn_registration_index_path,
          params: callback_params
      end.not_to(change { [User.count, Passkey.count] })
    end

    it "redirects to root with alert when passkey save fails and cleans session" do
      allow_any_instance_of(Passkey).to receive(:save).and_return(false)

      expect do
        post callback_users_webauthn_registration_index_path,
          params: callback_params
      end.not_to(change { [User.count, Passkey.count] })

      expect(session_hash[:user_id]).to be_nil
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Couldn't register your Passkey")
      expect(session_hash[:current_registration]).to be_nil
    end

    it "redirects to root with the expired-session alert when current_registration is missing" do
      session_hash.delete(:current_registration)

      post callback_users_webauthn_registration_index_path,
        params: callback_params

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Registration session expired. Please try again.")
      expect(session_hash[:current_registration]).to be_nil
    end

    it "redirects to root with the expired-session alert when the verified phone is blank" do
      session_hash.delete(:verified_phone)

      expect do
        post callback_users_webauthn_registration_index_path,
          params: callback_params
      end.not_to(change { [User.count, Passkey.count] })

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Registration session expired. Please try again.")
      expect(session_hash[:current_registration]).to be_nil
    end

    it "redirects to root with the retry alert when another passkey has the same credential id" do
      create(:passkey, external_id: fake_credential_id)

      expect do
        post callback_users_webauthn_registration_index_path,
          params: callback_params
      end.not_to(change { [User.count, Passkey.count] })

      expect(session_hash[:user_id]).to be_nil
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Couldn't register your Passkey")
      expect(session_hash[:current_registration]).to be_nil
    end

    it "redirects to root with the retry alert when another passkey has the same public key" do
      create(:passkey, public_key: fake_public_key)

      expect do
        post callback_users_webauthn_registration_index_path,
          params: callback_params
      end.not_to(change { [User.count, Passkey.count] })

      expect(session_hash[:user_id]).to be_nil
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Couldn't register your Passkey")
      expect(session_hash[:current_registration]).to be_nil
    end

    it "keeps the saved account and redirects with the sign-in alert when signing in fails" do
      sign_in_error = RuntimeError.new("sign in failed")
      allow_any_instance_of(Users::Webauthn::RegistrationController).to receive(:sign_in).and_raise(sign_in_error)
      allow(Sentry).to receive(:capture_exception)

      expect do
        post callback_users_webauthn_registration_index_path,
          params: callback_params
      end.to change(User, :count).by(1).and change(Passkey, :count).by(1)

      expect(Passkey.last!.user).to eq(User.find_by!(phone: phone))
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(Users::Webauthn::RegistrationController::SIGN_IN_FAILED_MESSAGE)
      expect(flash[:alert]).to include("Sign in with your passkey")
      expect(Sentry).to have_received(:capture_exception).with(sign_in_error, anything)
      expect(session_hash[:current_registration]).to be_nil
    end

    it "enrolls the verified phone when the stored registration carries no user attributes" do
      session_hash[:current_registration] = {"challenge" => fake_challenge}

      expect do
        post callback_users_webauthn_registration_index_path,
          params: callback_params
      end.to change(User, :count).by(1).and change(Passkey, :count).by(1)

      expect(Passkey.last!.user).to eq(User.find_by!(phone: phone))
      expect(response).to redirect_to(sway_registration_index_path)
      expect(session_hash[:current_registration]).to be_nil
    end

    it "does not create records when current_registration is missing" do
      session_hash.delete(:current_registration)

      expect do
        post callback_users_webauthn_registration_index_path,
          params: callback_params
      end.not_to(change { [User.count, Passkey.count] })

      expect(session_hash[:current_registration]).to be_nil
    end

    it "redirects to root with alert and clears current_registration when user save fails" do
      create(:user, phone: phone)
      invalid_user = User.new
      invalid_user.errors.add(:base, "invalid user")
      allow_any_instance_of(User).to receive(:save!).and_raise(
        ActiveRecord::RecordInvalid.new(User.new)
      )
      allow_any_instance_of(User).to receive(:save!).and_raise(
        ActiveRecord::RecordInvalid.new(invalid_user)
      )

      post callback_users_webauthn_registration_index_path,
        params: callback_params

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Registration failed: invalid user")
      expect(session_hash[:current_registration]).to be_nil
      expect(Passkey.count).to eq(0)
    end

    it "redirects to root with alert and clears current_registration when new user save fails" do
      invalid_user = User.new
      invalid_user.errors.add(:base, "cannot save")

      allow_any_instance_of(User).to receive(:save!).and_raise(
        ActiveRecord::RecordInvalid.new(invalid_user)
      )

      post callback_users_webauthn_registration_index_path,
        params: callback_params

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Registration failed: cannot save")
      expect(session_hash[:current_registration]).to be_nil
      expect(Passkey.count).to eq(0)
    end
  end

  describe "only a phone that already has an account is refused" do
    let(:phone) { "4105553000" }
    let(:callback_params) do
      {
        id: fake_credential_id,
        rawId: Base64.strict_encode64(fake_credential_id),
        passkey_label: "MacBook"
      }
    end

    before do
      session_hash[:phone] = phone
      session_hash[:verified_phone] = phone
      session_hash[:verified_phone_at] = Time.current.to_i
    end

    it "gives a brand-new phone exactly one account and one passkey" do
      post users_webauthn_registration_index_path
      expect(response).to have_http_status(:ok)

      post callback_users_webauthn_registration_index_path, params: callback_params

      expect(response).to redirect_to(sway_registration_index_path)
      user = User.find_by!(phone: phone)
      expect(User.where(phone: phone).count).to eq(1)
      expect(user.passkeys.count).to eq(1)
    end

    it "lets a user row without a passkey enroll its first passkey without a second row" do
      user = create(:user, phone: phone, is_phone_verified: true)

      post users_webauthn_registration_index_path
      expect(response).to have_http_status(:ok)

      expect do
        post callback_users_webauthn_registration_index_path, params: callback_params
      end.not_to change(User, :count)

      expect(response).to redirect_to(sway_registration_index_path)
      expect(user.passkeys.count).to eq(1)
    end

    it "refuses a phone that already has a passkey at the start" do
      create(:passkey, user: create(:user, phone: phone))

      post users_webauthn_registration_index_path

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["errors"]).to eq([Users::Webauthn::RegistrationController::ALREADY_REGISTERED_MESSAGE])
    end

    context "when a concurrent enrollment saved the phone after this callback looked it up" do
      before do
        post users_webauthn_registration_index_path
        expect(response).to have_http_status(:ok)
        create(:passkey, user: create(:user, phone: phone))
      end

      it "answers already registered when the save fails the phone uniqueness validation" do
        allow(User).to receive(:find_or_initialize_by).and_return(User.new(phone: phone))

        expect do
          post callback_users_webauthn_registration_index_path, params: callback_params
        end.not_to(change { [User.count, Passkey.count] })

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(Users::Webauthn::RegistrationController::ALREADY_REGISTERED_MESSAGE)
        expect(session_hash[:user_id]).to be_nil
        expect(session_hash[:current_registration]).to be_nil
      end

      it "answers already registered when the save hits the unique phone index" do
        unsaved_duplicate = User.new(phone: phone)
        allow(unsaved_duplicate).to receive(:save!).and_wrap_original { |original| original.call(validate: false) }
        allow(User).to receive(:find_or_initialize_by).and_return(unsaved_duplicate)

        expect do
          post callback_users_webauthn_registration_index_path, params: callback_params
        end.not_to(change { [User.count, Passkey.count] })

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(Users::Webauthn::RegistrationController::ALREADY_REGISTERED_MESSAGE)
        expect(session_hash[:user_id]).to be_nil
        expect(session_hash[:current_registration]).to be_nil
      end
    end
  end

  describe "phone_taken?" do
    it "treats an error that is neither a failed validation nor a unique-index hit as no phone conflict" do
      error = StandardError.new("UNIQUE constraint failed: users.phone")

      expect(Users::Webauthn::RegistrationController.new.send(:phone_taken?, error)).to be(false)
    end
  end

  describe "an unexpected error" do
    let(:phone) { "4105552100" }

    before do
      session_hash[:phone] = phone
      session_hash[:verified_phone] = phone
      session_hash[:verified_phone_at] = Time.current.to_i
      allow(User).to receive(:find_or_initialize_by).and_raise(RuntimeError, "boom")
      allow(Sentry).to receive(:capture_exception)
    end

    it "answers 503 onboarding_unavailable to the JSON enrollment start and reports the error" do
      post users_webauthn_registration_index_path, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("error", "code")).to eq("onboarding_unavailable")
      expect(Sentry).to have_received(:capture_exception).with(an_instance_of(RuntimeError), any_args).once
    end

    it "redirects the web callback with a retry message, reports the error and clears the challenge" do
      session_hash[:current_registration] = {"challenge" => fake_challenge, "user_attributes" => {"phone" => phone}}

      post callback_users_webauthn_registration_index_path,
        params: {id: fake_credential_id, rawId: Base64.strict_encode64(fake_credential_id)}

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(OnboardingSafetyNet::ONBOARDING_UNAVAILABLE_MESSAGE)
      expect(Sentry).to have_received(:capture_exception).with(an_instance_of(RuntimeError), any_args).once
      expect(session_hash[:current_registration]).to be_nil
    end
  end
end
