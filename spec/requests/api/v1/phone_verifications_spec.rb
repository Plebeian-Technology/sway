# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::PhoneVerifications", type: :request do
  include_context "with in-memory Rails.cache"

  let(:phone) { "4105550456" }

  describe "POST /api/v1/phone_verification" do
    it "returns 204 when the skip switch is on (CI-friendly path)" do
      with_app_config(:dev_login, skip_phone_verification: true) do
        post "/api/v1/phone_verification",
          params: {phone: phone},
          as: :json
        expect(response).to have_http_status(:no_content)
      end
    end

    it "returns 400 bad_request when phone is missing" do
      post "/api/v1/phone_verification", params: {}, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(json_body.dig(:error, :code)).to eq("bad_request")
    end

    it "returns 422 invalid_phone when phone is not 10 digits" do
      post "/api/v1/phone_verification", params: {phone: "12345"}, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body.dig(:error, :code)).to eq("invalid_phone")
    end
  end

  describe "POST /api/v1/phone_verification/verify" do
    around do |ex|
      with_app_config(:dev_login, skip_phone_verification: true) { ex.run }
    end

    it "returns sms_verified_token + expires_at when code is valid (skip path)" do
      post "/api/v1/phone_verification/verify",
        params: {phone: phone, code: "000000"},
        as: :json

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body[:sms_verified_token]).to be_present
      expect(body[:expires_at]).to be_present

      stored = Rails.cache.read("sms_verified_token:#{body[:sms_verified_token]}")
      expect(stored).to be_present
      expect(stored[:phone]).not_to eq(phone)
      expect(stored[:phone]).to eq(PhoneCacheKey.digest(phone))
    end

    it "returns 400 bad_request when phone is missing" do
      post "/api/v1/phone_verification/verify", params: {code: "000000"}, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 bad_request when code is missing" do
      post "/api/v1/phone_verification/verify", params: {phone: phone}, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 422 invalid_phone when phone is not 10 digits on verify" do
      post "/api/v1/phone_verification/verify", params: {phone: "123", code: "000000"}, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body.dig(:error, :code)).to eq("invalid_phone")
    end

    it "returns 422 invalid_code when code is whitespace on verify" do
      post "/api/v1/phone_verification/verify", params: {phone: phone, code: "   "}, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body.dig(:error, :code)).to eq("invalid_code")
    end

    it "throttles after 5 verify attempts for the same phone within 10 minutes" do
      with_rate_limit_enabled(:phone_verify) do
        6.times do |i|
          post "/api/v1/phone_verification/verify",
            params: {phone: "+1 (410) 555-0456", code: "000000"},
            headers: {"REMOTE_ADDR" => "10.0.3.#{i + 1}"},
            as: :json
        end

        expect(response).to have_http_status(:too_many_requests)
        expect(json_body.dig(:error, :code)).to eq("rate_limited")
        expect(response.headers["Retry-After"]).to eq("600")
      end
    end

    it "throttles after 10 verify attempts from the same IP within 1 minute" do
      with_rate_limit_enabled(:phone_verify) do
        11.times do |i|
          post "/api/v1/phone_verification/verify",
            params: {phone: "410555#{i.to_s.rjust(4, "0")}", code: "000000"},
            headers: {"REMOTE_ADDR" => "10.0.4.1"},
            as: :json
        end

        expect(response).to have_http_status(:too_many_requests)
        expect(json_body.dig(:error, :code)).to eq("rate_limited")
        expect(response.headers["Retry-After"]).to eq("60")
      end
    end
  end

  # The message text on a Twilio::REST::RestError contains the phone number it was
  # sending to. Both mobile endpoints must log only the name of the event and Twilio's
  # numeric code, never the number.
  describe "Twilio error handling (no recipient-phone leak)" do
    include_context "TwilioDouble"

    around do |ex|
      # Exercise the real Twilio path.
      with_app_config(:dev_login, skip_phone_verification: false) { ex.run }
    end

    it "request_code logs only safe fields and returns 503 when Twilio raises" do
      twilio_error = Twilio::REST::RestError.allocate
      allow(twilio_error).to receive(:code).and_return(21_211)
      allow(twilio_error).to receive(:full_message).and_return(
        "The 'To' number +14105550456 is not a valid phone number."
      )
      allow(twilio_verifications_double).to receive(:create).and_raise(twilio_error)
      logged = [] #: Array[String]
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }

      post "/api/v1/phone_verification", params: {phone: phone}, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json_body.dig(:error, :code)).to eq("verification_unavailable")
      expect(logged.join("\n")).to include("api_v1.phone_verification.create_failed")
      expect(logged.join("\n")).not_to include("4105550456")
    end

    it "verify logs only safe fields and returns invalid_code when Twilio raises" do
      twilio_error = Twilio::REST::RestError.allocate
      allow(twilio_error).to receive(:code).and_return(60_200)
      allow(twilio_error).to receive(:full_message).and_return(
        "The 'To' number +14105550456 is not a valid phone number."
      )
      allow(twilio_verification_checks_double).to receive(:create).and_raise(twilio_error)
      logged = [] #: Array[String]
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }

      post "/api/v1/phone_verification/verify",
        params: {phone: phone, code: "000000"},
        as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(logged.join("\n")).to include("api_v1.phone_verification.verify_failed")
      expect(logged.join("\n")).not_to include("4105550456")
    end

    context "when Twilio cannot be reached" do
      it "request_code answers 503 verification_unavailable" do
        allow(twilio_verifications_double).to receive(:create).and_raise(
          Twilio::REST::TwilioError.new("execution expired +14105550456")
        )
        logged = [] #: Array[String]
        allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }

        post "/api/v1/phone_verification", params: {phone: phone}, as: :json

        expect(response).to have_http_status(:service_unavailable)
        expect(json_body.dig(:error, :code)).to eq("verification_unavailable")
        expect(response.body).not_to include("4105550456")
        expect(logged.join("\n")).to include("api_v1.phone_verification.create_failed")
        expect(logged.join("\n")).not_to include("4105550456")
      end

      it "verify answers 503 verification_unavailable, not invalid_code" do
        allow(twilio_verification_checks_double).to receive(:create).and_raise(
          Twilio::REST::TwilioError.new("execution expired +14105550456")
        )
        logged = [] #: Array[String]
        allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }

        post "/api/v1/phone_verification/verify",
          params: {phone: phone, code: "000000"},
          as: :json

        expect(response).to have_http_status(:service_unavailable)
        expect(json_body.dig(:error, :code)).to eq("verification_unavailable")
        expect(response.body).not_to include("4105550456")
        expect(logged.join("\n")).to include("api_v1.phone_verification.verify_failed")
        expect(logged.join("\n")).not_to include("4105550456")
      end
    end
  end

  describe "when the Twilio Verify service id is not set" do
    include_context "TwilioDouble"

    around do |ex|
      with_app_config(:dev_login, skip_phone_verification: false) do
        with_env(
          "TWILIO_ACCOUNT_SID" => "AC00000000000000000000000000000000",
          "TWILIO_AUTH_TOKEN" => "test-auth-token",
          "TWILIO_VERIFY_SERVICE_SID" => nil
        ) { ex.run }
      end
    end

    before do
      allow(Twilio::REST::Client).to receive(:new).and_call_original
      allow(Sentry).to receive(:capture_exception)
    end

    it "request_code answers 503 verification_unavailable and reports the missing setting" do
      post "/api/v1/phone_verification", params: {phone: phone}, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json_body.dig(:error, :code)).to eq("verification_unavailable")
      expect(Sentry).to have_received(:capture_exception)
        .with(an_instance_of(Authentication::VerifyServiceNotConfiguredError)).once
    end

    it "verify answers 503 verification_unavailable and reports the missing setting" do
      post "/api/v1/phone_verification/verify",
        params: {phone: phone, code: "000000"},
        as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json_body.dig(:error, :code)).to eq("verification_unavailable")
      expect(Sentry).to have_received(:capture_exception)
        .with(an_instance_of(Authentication::VerifyServiceNotConfiguredError)).once
    end
  end

  describe "with the skip switch off (Twilio answers)" do
    include_context "TwilioDouble"

    around do |ex|
      with_app_config(:dev_login, skip_phone_verification: false) { ex.run }
    end

    describe "POST /api/v1/phone_verification" do
      it "sends an SMS code to the normalized +1 number and answers 204" do
        post "/api/v1/phone_verification", params: {phone: "(410) 555-0456"}, as: :json

        expect(response).to have_http_status(:no_content)
        expect(twilio_verifications_double).to have_received(:create).with(to: "+14105550456", channel: "sms").once
      end

      it "answers 422 invalid_phone without calling Twilio for a number no US phone can have" do
        post "/api/v1/phone_verification", params: {phone: "1234567890"}, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_body.dig(:error, :code)).to eq("invalid_phone")
        expect(twilio_verifications_double).not_to have_received(:create)
      end

      it "lets 30 requests from one IP through and refuses the 31st with 429 rate_limited" do
        with_rate_limit_enabled(:phone_verify) do
          30.times do |i|
            post "/api/v1/phone_verification", params: {phone: "410555#{i.to_s.rjust(4, "0")}"}, as: :json
            expect(response).to have_http_status(:no_content)
          end

          post "/api/v1/phone_verification", params: {phone: "4105550030"}, as: :json

          expect(response).to have_http_status(:too_many_requests)
          expect(json_body.dig(:error, :code)).to eq("rate_limited")
          expect(response.headers["Retry-After"]).to eq("3600")
          expect(twilio_verifications_double).to have_received(:create).exactly(30).times
        end
      end
    end

    describe "POST /api/v1/phone_verification/verify" do
      it "issues a token bound to the phone digest when Twilio approves the code" do
        post "/api/v1/phone_verification/verify", params: {phone: phone, code: "123456"}, as: :json

        expect(response).to have_http_status(:ok)
        expect(twilio_verification_checks_double).to have_received(:create).with(to: "+14105550456", code: "123456")
        body = json_body
        expect(body[:expires_at]).to be_present
        stored = Rails.cache.read("sms_verified_token:#{body[:sms_verified_token]}")
        expect(stored[:phone]).to eq(PhoneCacheKey.digest(phone))
        expect(stored[:phone]).not_to eq(phone)
      end

      it "answers 422 invalid_phone without calling Twilio for a number no US phone can have" do
        post "/api/v1/phone_verification/verify", params: {phone: "1234567890", code: "123456"}, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_body.dig(:error, :code)).to eq("invalid_phone")
        expect(twilio_verification_checks_double).not_to have_received(:create)
      end

      context "when Twilio answers pending" do
        let(:twilio_verification_status) { "pending" }

        it "answers 401 invalid_code and issues no token" do
          written_keys = [] #: Array[String]
          allow(Rails.cache).to receive(:write).and_wrap_original do |original, key, *rest, **options|
            written_keys << key.to_s
            original.call(key, *rest, **options)
          end

          post "/api/v1/phone_verification/verify", params: {phone: phone, code: "123456"}, as: :json

          expect(response).to have_http_status(:unauthorized)
          expect(json_body.dig(:error, :code)).to eq("invalid_code")
          expect(json_body).not_to have_key(:sms_verified_token)
          expect(written_keys.grep(/\Asms_verified_token:/)).to be_empty
        end
      end
    end
  end

  describe "an unexpected error" do
    around do |ex|
      with_app_config(:dev_login, skip_phone_verification: false) { ex.run }
    end

    before do
      allow(Sway::TwilioClient).to receive(:build).and_raise(RuntimeError, "boom")
      allow(Sentry).to receive(:capture_exception)
    end

    it "answers 503 onboarding_unavailable and reports the error" do
      post "/api/v1/phone_verification", params: {phone: phone}, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json_body.dig(:error, :code)).to eq("onboarding_unavailable")
      expect(Sentry).to have_received(:capture_exception).with(an_instance_of(RuntimeError), any_args).once
    end

    it "keeps the 400 bad_request answer for a missing phone" do
      post "/api/v1/phone_verification", params: {}, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(json_body.dig(:error, :code)).to eq("bad_request")
      expect(Sentry).not_to have_received(:capture_exception)
    end
  end
end
