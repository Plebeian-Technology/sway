require "rails_helper"

RSpec.describe "Users::Webauthn::Registration", type: :request do
  include_context "SessionDouble"
  include_context "WebAuthnDouble"

  describe "POST /users/webauthn/registration" do
    let(:phone) { "4105551000" }

    context "when phone is verified" do
      before do
        session_hash[:phone] = phone
        session_hash[:verified_phone] = phone
      end

      it "returns 422 when user attributes are invalid" do
        user_errors =
          instance_double(ActiveModel::Errors, full_messages: ["user invalid"])
        allow_any_instance_of(User).to receive(:valid?).and_return(false)
        allow_any_instance_of(User).to receive(:errors).and_return(user_errors)

        post users_webauthn_registration_index_path

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq({ "errors" => ["user invalid"] })
        expect(session_hash[:current_registration]).to be_nil
      end

      it "returns registration options with challenge" do
        post users_webauthn_registration_index_path

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["challenge"]).to eq(fake_challenge)
      end

      it "stores challenge and user attributes in session" do
        post users_webauthn_registration_index_path

        expect(session_hash.dig(:current_registration, :challenge)).to eq(
          fake_challenge,
        )
        expect(
          session_hash.dig(:current_registration, :user_attributes),
        ).to include("phone" => phone)
      end

      it "passes existing credential ids in exclude" do
        user = create(:user, phone: phone)
        first_passkey =
          create(:passkey, user: user, external_id: "credential-1")
        second_passkey =
          create(:passkey, user: user, external_id: "credential-2")

        expect_any_instance_of(WebAuthn::RelyingParty).to receive(
          :options_for_registration,
        ).with(
          hash_including(
            exclude:
              match_array(
                [first_passkey.external_id, second_passkey.external_id],
              ),
          ),
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
            "message" => "Please confirm your phone number first.",
          },
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
        passkey_label: "MacBook",
      }
    end

    before do
      session_hash[:verified_phone] = phone
      session_hash[:current_registration] = {
        "challenge" => fake_challenge,
        "user_attributes" => {
          "phone" => phone,
          "is_registration_complete" => false,
        },
      }
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
    end

    it "resets old session data before setting user_id" do
      session_hash[:attacker_session] = "stale"

      post callback_users_webauthn_registration_index_path,
           params: callback_params

      expect(session_hash[:attacker_session]).to be_nil
      expect(session_hash[:user_id]).to eq(User.find_by(phone: phone)&.id)
    end

    it "writes a refresh token cookie on sign in" do
      post callback_users_webauthn_registration_index_path,
           params: callback_params

      expect(cookies_hash[:refresh_token]).to eq({ value: "refresh-token" })
    end

    it "returns the registration route" do
      post callback_users_webauthn_registration_index_path,
           params: callback_params

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["route"]).to eq(SwayRoutes::REGISTRATION)
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
    end

    it "returns 422 when WebAuthn verification fails" do
      allow_any_instance_of(WebAuthn::RelyingParty).to receive(
        :verify_registration,
      ).and_raise(WebAuthn::Error, "bad attestation")

      post callback_users_webauthn_registration_index_path,
           params: callback_params

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["message"]).to eq(
        "Verification failed: bad attestation",
      )
      expect(session_hash[:current_registration]).to be_nil
    end

    it "does not persist user or passkey when WebAuthn verification fails" do
      allow_any_instance_of(WebAuthn::RelyingParty).to receive(
        :verify_registration,
      ).and_raise(WebAuthn::Error, "bad attestation")

      expect do
        post callback_users_webauthn_registration_index_path,
             params: callback_params
      end.not_to(change { [User.count, Passkey.count] })
    end

    it "returns 422 when passkey save fails and cleans session" do
      allow_any_instance_of(Passkey).to receive(:save).and_return(false)

      post callback_users_webauthn_registration_index_path,
           params: callback_params

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq(
        { "success" => false, "message" => "Couldn't register your Passkey" },
      )
      expect(session_hash[:current_registration]).to be_nil
    end

    it "returns an error response when current_registration is missing" do
      session_hash.delete(:current_registration)

      post callback_users_webauthn_registration_index_path,
           params: callback_params

      expect(response).not_to have_http_status(:ok)
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

    it "returns 422 and clears current_registration when user save fails" do
      create(:user, phone: phone)
      invalid_user = User.new
      invalid_user.errors.add(:base, "invalid user")
      allow_any_instance_of(User).to receive(:save!).and_raise(
        ActiveRecord::RecordInvalid.new(User.new),
      )
      allow_any_instance_of(User).to receive(:save!).and_raise(
        ActiveRecord::RecordInvalid.new(invalid_user),
      )

      post callback_users_webauthn_registration_index_path,
           params: callback_params

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq(
        { "success" => false, "errors" => ["invalid user"] },
      )
      expect(session_hash[:current_registration]).to be_nil
      expect(Passkey.count).to eq(0)
    end

    it "returns 422 and clears current_registration when new user save fails" do
      invalid_user = User.new
      invalid_user.errors.add(:base, "cannot save")

      allow_any_instance_of(User).to receive(:save!).and_raise(
        ActiveRecord::RecordInvalid.new(invalid_user),
      )

      post callback_users_webauthn_registration_index_path,
           params: callback_params

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq(
        { "success" => false, "errors" => ["cannot save"] },
      )
      expect(session_hash[:current_registration]).to be_nil
      expect(Passkey.count).to eq(0)
    end
  end
end
