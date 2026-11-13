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
end
