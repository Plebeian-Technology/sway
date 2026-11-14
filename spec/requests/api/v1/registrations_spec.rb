# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Registrations", type: :request do
  include_context "with in-memory Rails.cache"

  let(:phone) { "4105557777" }

  describe "POST /api/v1/registrations" do
    it "returns WebAuthn registration options when sms_verified_token is valid" do
      token = SmsVerificationToken.issue!(phone)

      post "/api/v1/registrations",
        params: {registration: {sms_verified_token: token, phone: phone}},
        as: :json

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body[:challenge_id]).to be_present
      expect(body[:challenge]).to be_present
      # The shape the WebAuthn spec defines for a create request: a nested rp object,
      # pubKeyCredParams, and camelCase key names. react-native-passkey refuses
      # anything else.
      expect(body.dig(:rp, :id)).to be_present
      expect(body.dig(:rp, :name)).to be_present
      expect(body[:user]).to be_present
      expect(body[:pubKeyCredParams]).to be_an(Array).and(be_present)
      # @lat: [[discoverable-passkey-design#Why registration asks for resident_key: "preferred"]]
      expect(body.dig(:authenticatorSelection, :residentKey)).to eq("preferred")

      cached = Rails.cache.read("webauthn:challenge:#{body[:challenge_id]}")
      expect(cached).to be_present
      expect(cached[:phone]).to eq(phone)
      expect(cached[:sms_verified_token]).to eq(token)
      expect(cached[:webauthn_id]).to eq(body.dig(:user, :id))
    end

    it "normalizes a formatted phone input to 10 digits before checking and caching" do
      user = create(:user, phone: phone)
      create(:passkey, user: user)
      token = SmsVerificationToken.issue!(phone)

      post "/api/v1/registrations",
        params: {registration: {sms_verified_token: token, phone: "+1 (410) 555-7777"}},
        as: :json

      expect(response).to have_http_status(:conflict)
      expect(json_body.dig(:error, :code)).to eq("phone_already_registered")
    end

    it "returns 401 invalid_sms_token when token is missing" do
      post "/api/v1/registrations",
        params: {registration: {sms_verified_token: "deadbeef", phone: phone}},
        as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_sms_token")
    end

    it "returns 401 invalid_sms_token when phone does not match the bound phone" do
      token = SmsVerificationToken.issue!(phone)
      post "/api/v1/registrations",
        params: {registration: {sms_verified_token: token, phone: "9999999999"}},
        as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_sms_token")
    end

    # Verifying by text and then creating a passkey is how any phone number without a
    # passkey gets started — including numbers that already have a User row, such as a
    # seeded admin, or a web account that never finished setting a passkey up. The only
    # reason to refuse is a passkey that already exists.
    it "returns 200 when the phone has a User row but no passkey" do
      create(:user, phone: phone)
      token = SmsVerificationToken.issue!(phone)

      post "/api/v1/registrations",
        params: {registration: {sms_verified_token: token, phone: phone}},
        as: :json

      expect(response).to have_http_status(:ok)
      expect(json_body[:challenge_id]).to be_present
    end

    it "returns 409 phone_already_registered when the phone already has a passkey" do
      user = create(:user, phone: phone)
      create(:passkey, user: user)
      token = SmsVerificationToken.issue!(phone)

      post "/api/v1/registrations",
        params: {registration: {sms_verified_token: token, phone: phone}},
        as: :json

      expect(response).to have_http_status(:conflict)
      expect(json_body.dig(:error, :code)).to eq("phone_already_registered")
    end
  end

  describe "POST /api/v1/registrations/callback" do
    it "returns 401 invalid_challenge when cache key is missing" do
      empty_credential = {}
      # @type var empty_credential: Hash[Symbol, untyped]
      post "/api/v1/registrations/callback",
        params: {registration: {challenge_id: "deadbeef", credential: empty_credential, platform: "ios"}},
        as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("invalid_challenge")
    end

    # Walk the success path, so the user data sent back alongside the bearer token
    # (build_bearer_token_payload, which calls user.to_sway_json) gets the same "these
    # fields must be absent" check as the web pages, the bootstrap call and the
    # sessions callback.
    context "when registration succeeds (bearer envelope)" do
      include_context "WebAuthnDouble"

      it "excludes sensitive user fields from the issued user payload" do
        # Force the non-admin case, so is_admin is certain to be absent.
        User.send(:remove_const, :ADMIN_PHONES)
        User.const_set(:ADMIN_PHONES, ["+10000000000"])
        token = SmsVerificationToken.issue!(phone)
        Rails.cache.write(
          "webauthn:challenge:reg-net",
          {challenge: fake_challenge, sms_verified_token: token, phone: phone},
          expires_in: 5.minutes
        )

        post "/api/v1/registrations/callback",
          params: {registration: {challenge_id: "reg-net", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:ok)
        user_payload = json_body[:user]
        %w[current_sign_in_ip last_sign_in_ip webauthn_id sign_in_count is_admin].each do |field|
          expect(user_payload).not_to have_key(field.to_sym)
          expect(user_payload).not_to have_key(field)
        end
      end

      it "answers with exactly the session envelope keys the mobile app stores" do
        token = SmsVerificationToken.issue!(phone)
        Rails.cache.write(
          "webauthn:challenge:reg-envelope",
          {challenge: fake_challenge, sms_verified_token: token, phone: phone},
          expires_in: 5.minutes
        )

        post "/api/v1/registrations/callback",
          params: {registration: {challenge_id: "reg-envelope", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:ok)
        body = json_body
        expect(body.keys).to match_array(%i[bearer_token device_id user expires_at])
        expect(body[:bearer_token]).to match(/\A\h{64}\z/)

        user = User.find_by!(phone: phone)
        expect(body[:device_id]).to eq(UserDevice.find_by!(user: user).id)
        expect(body.dig(:user, :id)).to eq(user.id)
        expect(Time.iso8601(body[:expires_at])).to be_between(89.days.from_now, 91.days.from_now)
      end

      it "issues a bearer token that alone can complete address registration" do
        sway_locale = create(:sway_locale, city: "Baltimore", state: "MD", country: "US")
        legislator = create(:legislator, district: create(:district, sway_locale: sway_locale))
        allow(SwayLocale).to receive(:find_or_create_by_normalized!).and_return(sway_locale)
        allow_any_instance_of(SwayRegistrationService).to receive(:call) do # rubocop:disable RSpec/AnyInstance
          UserLegislator.find_or_create_by!(user: User.find_by!(phone: phone), legislator: legislator)
        end
        token = SmsVerificationToken.issue!(phone)
        Rails.cache.write(
          "webauthn:challenge:reg-address",
          {challenge: fake_challenge, sms_verified_token: token, phone: phone},
          expires_in: 5.minutes
        )

        post "/api/v1/registrations/callback",
          params: {registration: {challenge_id: "reg-address", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json
        expect(response).to have_http_status(:ok)
        bearer_token = json_body[:bearer_token]
        reset!

        post "/sway_registration",
          params: {
            sway_registration: {
              street: "100 N Holliday St",
              street2: "",
              city: "Baltimore",
              region_code: "MD",
              postal_code: "21202",
              country: "US",
              latitude: 39.29105,
              longitude: -76.61069
            }
          },
          headers: {"Authorization" => "Bearer #{bearer_token}", "Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq("ok" => true, "registration_status" => "completed")
        user = User.find_by!(phone: phone)
        expect(user).to be_registered
        expect(UserLegislator.find_by!(user: user, legislator: legislator).active).to be(true)
      end

      it "rejects a second callback minted from the same sms_verified_token with 401 invalid_sms_token" do
        token = SmsVerificationToken.issue!(phone)
        post "/api/v1/registrations",
          params: {registration: {sms_verified_token: token, phone: phone}},
          as: :json
        first_challenge_id = json_body[:challenge_id]

        post "/api/v1/registrations",
          params: {registration: {sms_verified_token: token, phone: phone}},
          as: :json
        second_challenge_id = json_body[:challenge_id]

        post "/api/v1/registrations/callback",
          params: {registration: {challenge_id: first_challenge_id, credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json
        expect(response).to have_http_status(:ok)
        device_count_before = UserDevice.count

        expect {
          post "/api/v1/registrations/callback",
            params: {registration: {challenge_id: second_challenge_id, credential: {id: "y", type: "public-key"}, platform: "ios"}},
            as: :json
        }.not_to change(Passkey, :count)
        expect(UserDevice.count).to eq(device_count_before)

        expect(response).to have_http_status(:unauthorized)
        expect(json_body.dig(:error, :code)).to eq("invalid_sms_token")
        expect(Rails.cache.read("webauthn:challenge:#{second_challenge_id}")).to be_nil
      end

      it "deletes the challenge from Rails.cache when verify_registration raises WebAuthn::Error" do
        token = SmsVerificationToken.issue!(phone)
        Rails.cache.write(
          "webauthn:challenge:reg-fail",
          {challenge: fake_challenge, sms_verified_token: token, phone: phone},
          expires_in: 5.minutes
        )
        allow_any_instance_of(WebAuthn::RelyingParty).to receive(:verify_registration)
          .and_raise(WebAuthn::Error.new("bad attestation"))

        post "/api/v1/registrations/callback",
          params: {registration: {challenge_id: "reg-fail", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(json_body.dig(:error, :code)).to eq("invalid_credentials")
        expect(Rails.cache.read("webauthn:challenge:reg-fail")).to be_nil
        expect(SmsVerificationToken.peek(token)).to be_present
      end

      it "persists the cached webauthn_id on the created user in callback" do
        token = SmsVerificationToken.issue!(phone)
        Rails.cache.write(
          "webauthn:challenge:reg-wid",
          {challenge: fake_challenge, sms_verified_token: token, phone: phone, webauthn_id: "consistent-wid-123"},
          expires_in: 5.minutes
        )

        post "/api/v1/registrations/callback",
          params: {registration: {challenge_id: "reg-wid", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:ok)
        expect(User.find_by!(phone: phone).webauthn_id).to eq("consistent-wid-123")
      end

      it "does not consume sms_verified_token when passkey validation fails" do
        other_user = create(:user, phone: "4105558888")
        create(:passkey, user: other_user, external_id: fake_credential_id)
        token = SmsVerificationToken.issue!(phone)
        Rails.cache.write(
          "webauthn:challenge:reg-dup-cred",
          {challenge: fake_challenge, sms_verified_token: token, phone: phone, webauthn_id: "wid-456"},
          expires_in: 5.minutes
        )

        post "/api/v1/registrations/callback",
          params: {registration: {challenge_id: "reg-dup-cred", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_body.dig(:error, :code)).to eq("invalid_passkey")
        expect(SmsVerificationToken.peek(token)).to be_present
        expect(User.find_by(phone: phone)).to be_nil
      end
    end

    context "when account creation fails after the passkey is verified" do
      include_context "WebAuthnDouble"

      it "answers 503 and keeps the sms_verified_token when seeding notification preferences raises" do
        token = SmsVerificationToken.issue!(phone)
        Rails.cache.write(
          "webauthn:challenge:reg-seed-fail",
          {challenge: fake_challenge, sms_verified_token: token, phone: phone},
          expires_in: 5.minutes
        )
        allow(NotificationPreference).to receive(:seed_defaults_for).and_raise(StandardError, "seed failed")

        post "/api/v1/registrations/callback",
          params: {registration: {challenge_id: "reg-seed-fail", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:service_unavailable)
        expect(json_body.dig(:error, :code)).to eq("onboarding_unavailable")

        expect(User.find_by(phone: phone)).to be_nil
        expect(Passkey.count).to eq(0)
        expect(UserDevice.count).to eq(0)
        expect(SmsVerificationToken.peek(token)).to be_present
      end

      it "answers 503 and keeps the sms_verified_token when saving the passkey raises ActiveRecord::RecordNotUnique" do
        token = SmsVerificationToken.issue!(phone)
        Rails.cache.write(
          "webauthn:challenge:reg-save-fail",
          {challenge: fake_challenge, sms_verified_token: token, phone: phone},
          expires_in: 5.minutes
        )
        allow_any_instance_of(Passkey).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique) # rubocop:disable RSpec/AnyInstance

        post "/api/v1/registrations/callback",
          params: {registration: {challenge_id: "reg-save-fail", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:service_unavailable)
        expect(json_body.dig(:error, :code)).to eq("onboarding_unavailable")

        expect(User.find_by(phone: phone)).to be_nil
        expect(Passkey.count).to eq(0)
        expect(UserDevice.count).to eq(0)
        expect(SmsVerificationToken.peek(token)).to be_present
      end

      it "returns 409 phone_already_registered and keeps the token when the phone gains a passkey before the callback" do
        token = SmsVerificationToken.issue!(phone)
        Rails.cache.write(
          "webauthn:challenge:reg-raced",
          {challenge: fake_challenge, sms_verified_token: token, phone: phone},
          expires_in: 5.minutes
        )
        create(:passkey, user: create(:user, phone: phone))

        post "/api/v1/registrations/callback",
          params: {registration: {challenge_id: "reg-raced", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:conflict)
        expect(json_body.dig(:error, :code)).to eq("phone_already_registered")
        expect(SmsVerificationToken.peek(token)).to be_present
      end

      it "returns 401 invalid_sms_token, creates nothing and deletes the challenge when consume! returns false" do
        token = SmsVerificationToken.issue!(phone)
        Rails.cache.write(
          "webauthn:challenge:reg-consume-false",
          {challenge: fake_challenge, sms_verified_token: token, phone: phone},
          expires_in: 5.minutes
        )
        allow(SmsVerificationToken).to receive(:consume!).and_return(false)

        post "/api/v1/registrations/callback",
          params: {registration: {challenge_id: "reg-consume-false", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(json_body.dig(:error, :code)).to eq("invalid_sms_token")
        expect(User.find_by(phone: phone)).to be_nil
        expect(Passkey.count).to eq(0)
        expect(UserDevice.count).to eq(0)
        expect(Rails.cache.read("webauthn:challenge:reg-consume-false")).to be_nil
      end
    end

    context "when the phone has a user with no passkey and an unverified phone" do
      include_context "WebAuthnDouble"

      it "reuses that user and marks the phone verified" do
        existing = create(:user, phone: phone, is_phone_verified: false)
        token = SmsVerificationToken.issue!(phone)
        Rails.cache.write(
          "webauthn:challenge:reg-existing",
          {challenge: fake_challenge, sms_verified_token: token, phone: phone},
          expires_in: 5.minutes
        )

        post "/api/v1/registrations/callback",
          params: {registration: {challenge_id: "reg-existing", credential: {id: "x", type: "public-key"}, platform: "ios"}},
          as: :json

        expect(response).to have_http_status(:ok)
        expect(User.where(phone: phone).count).to eq(1)
        expect(existing.reload.is_phone_verified).to be(true)
        expect(Passkey.find_by!(external_id: fake_credential_id).user).to eq(existing)
      end
    end
  end

  describe "only a phone that already has an account is refused" do
    include_context "WebAuthnDouble"

    def start_registration
      token = SmsVerificationToken.issue!(phone)
      post "/api/v1/registrations",
        params: {registration: {sms_verified_token: token, phone: phone}},
        as: :json
    end

    def finish_registration(challenge_id)
      post "/api/v1/registrations/callback",
        params: {registration: {challenge_id: challenge_id, credential: {id: "x", type: "public-key"}, platform: "ios"}},
        as: :json
    end

    it "gives a brand-new phone exactly one account and one passkey" do
      start_registration
      expect(response).to have_http_status(:ok)

      finish_registration(json_body[:challenge_id])

      expect(response).to have_http_status(:ok)
      expect(User.where(phone: phone).count).to eq(1)
      expect(User.find_by!(phone: phone).passkeys.count).to eq(1)
    end

    it "lets a user row without a passkey enroll its first passkey without a second row" do
      user = create(:user, phone: phone)

      start_registration
      expect(response).to have_http_status(:ok)

      expect { finish_registration(json_body[:challenge_id]) }.not_to change(User, :count)

      expect(response).to have_http_status(:ok)
      expect(user.passkeys.count).to eq(1)
    end

    it "refuses a phone that already has a passkey at the start" do
      create(:passkey, user: create(:user, phone: phone))

      start_registration

      expect(response).to have_http_status(:conflict)
      expect(json_body.dig(:error, :code)).to eq("phone_already_registered")
    end

    context "when a concurrent registration saved the phone after this callback looked it up" do
      let!(:challenge_id) do
        start_registration
        expect(response).to have_http_status(:ok)
        json_body[:challenge_id]
      end

      before do
        create(:passkey, user: create(:user, phone: phone))
        allow(User).to receive(:find_by).and_call_original
        allow(User).to receive(:find_by).with(phone: phone).and_return(nil)
      end

      it "answers 409 phone_already_registered when the create fails the phone uniqueness validation" do
        expect { finish_registration(challenge_id) }
          .not_to(change { [User.count, Passkey.count, UserDevice.count] })

        expect(response).to have_http_status(:conflict)
        expect(json_body.dig(:error, :code)).to eq("phone_already_registered")
      end

      it "answers 409 phone_already_registered when the create hits the unique phone index" do
        allow(User).to receive(:create!).and_wrap_original do |_original, **attributes|
          User.new(attributes).tap { |user| user.save!(validate: false) }
        end

        expect { finish_registration(challenge_id) }
          .not_to(change { [User.count, Passkey.count, UserDevice.count] })

        expect(response).to have_http_status(:conflict)
        expect(json_body.dig(:error, :code)).to eq("phone_already_registered")
      end
    end
  end

  # @lat: [[phone-verification-rate-limits#Why Api::V1::RegistrationsController.create is rate-limited per IP]]
  describe "rate limiting (account-enumeration bound)" do
    it "throttles registration starts per IP after 5 attempts" do
      with_rate_limit_enabled(:sign_up) do
        6.times do
          post "/api/v1/registrations",
            params: {registration: {sms_verified_token: "deadbeef", phone: phone}},
            as: :json
        end

        expect(response).to have_http_status(:too_many_requests)
        expect(json_body.dig(:error, :code)).to eq("rate_limited")
      end
    end
  end

  describe "an unexpected error" do
    before do
      allow(SmsVerificationToken).to receive(:peek).and_raise(RuntimeError, "boom")
      allow(Sentry).to receive(:capture_exception)
    end

    it "answers 503 onboarding_unavailable and reports the error" do
      post "/api/v1/registrations",
        params: {registration: {sms_verified_token: "token", phone: phone}},
        as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json_body.dig(:error, :code)).to eq("onboarding_unavailable")
      expect(Sentry).to have_received(:capture_exception).with(an_instance_of(RuntimeError), any_args).once
    end
  end
end
