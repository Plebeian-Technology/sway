require "rails_helper"

RSpec.describe "PhoneVerification", type: :request do
  include_context "SessionDouble"
  include_context "TwilioDouble"

  describe "POST /phone_verification" do
    let(:params) { { phone_verification: { phone: "(410) 555-1212" } } }

    context "when SKIP_PHONE_VERIFICATION is enabled" do
      around do |example|
        previous = ENV["SKIP_PHONE_VERIFICATION"]
        ENV["SKIP_PHONE_VERIFICATION"] = "1"
        example.run
      ensure
        previous.nil? ? ENV.delete("SKIP_PHONE_VERIFICATION") : ENV["SKIP_PHONE_VERIFICATION"] = previous
      end

      it "stores phone in session and returns success" do
        post phone_verification_index_path, params: params

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({ "success" => true })
        expect(session_hash[:phone]).to eq("(410) 555-1212")
      end
    end

    context "when SKIP_PHONE_VERIFICATION is disabled" do
      around do |example|
        previous = ENV["SKIP_PHONE_VERIFICATION"]
        ENV.delete("SKIP_PHONE_VERIFICATION")
        example.run
      ensure
        previous.nil? ? ENV.delete("SKIP_PHONE_VERIFICATION") : ENV["SKIP_PHONE_VERIFICATION"] = previous
      end

      it "sends a Twilio verification and returns success" do
        post phone_verification_index_path, params: params

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({ "success" => true })
        expect(session_hash[:phone]).to eq("4105551212")
      end

      it "returns false when Twilio raises an error" do
        allow_any_instance_of(PhoneVerificationController).to receive(
          :send_phone_verification,
        ).and_return(false)

        post phone_verification_index_path, params: params

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({ "success" => false })
      end
    end
  end

  describe "PATCH /phone_verification/:id" do
    let(:params) { { phone_verification: { code: "123456" } } }

    around do |example|
      previous = ENV["SKIP_PHONE_VERIFICATION"]
      ENV.delete("SKIP_PHONE_VERIFICATION")
      example.run
    ensure
      previous.nil? ? ENV.delete("SKIP_PHONE_VERIFICATION") : ENV["SKIP_PHONE_VERIFICATION"] = previous
    end

    before do
      session_hash[:phone] = "4105551212"
    end

    it "stores verified_phone and returns success when approved" do
      patch phone_verification_path("1"), params: params

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({ "success" => true })
      expect(session_hash[:verified_phone]).to eq("4105551212")
    end

    it "returns false and does not store verified_phone when not approved" do
      allow(twilio_verification_result).to receive(:status).and_return("pending")

      patch phone_verification_path("1"), params: params

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({ "success" => false })
      expect(session_hash[:verified_phone]).to be_nil
    end

    it "redirects with an alert when Twilio returns 20404" do
      twilio_error = Twilio::REST::RestError.allocate
      allow(twilio_error).to receive(:code).and_return(20_404)
      allow(twilio_error).to receive(:message).and_return("VerificationCheck was not found")
      allow(twilio_verification_result).to receive(:status).and_raise(twilio_error)

      patch phone_verification_path("1"), params: params

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("SMS verification not found. Please try again.")
    end

    it "re-raises unexpected Twilio errors" do
      twilio_error = Twilio::REST::RestError.allocate
      allow(twilio_error).to receive(:code).and_return(50_000)
      allow(twilio_error).to receive(:message).and_return("twilio unavailable")
      allow(twilio_verification_result).to receive(:status).and_raise(twilio_error)

      expect do
        patch phone_verification_path("1"), params: params
      end.to raise_error(Twilio::REST::RestError)
    end

    it "does not create a user after verification" do
      expect do
        patch phone_verification_path("1"), params: params
      end.not_to change(User, :count)
    end
  end
end
