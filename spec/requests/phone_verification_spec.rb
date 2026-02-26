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
        previous.nil? ?
          ENV.delete("SKIP_PHONE_VERIFICATION") :
          ENV["SKIP_PHONE_VERIFICATION"] = previous
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
        previous.nil? ?
          ENV.delete("SKIP_PHONE_VERIFICATION") :
          ENV["SKIP_PHONE_VERIFICATION"] = previous
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
      previous.nil? ?
        ENV.delete("SKIP_PHONE_VERIFICATION") :
        ENV["SKIP_PHONE_VERIFICATION"] = previous
    end

    before { session_hash[:phone] = "4105551212" }

    it "stores verified_phone and returns success when approved" do
      patch phone_verification_path("1"), params: params

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({ "success" => true })
      expect(session_hash[:verified_phone]).to eq("4105551212")
    end

    it "returns false and does not store verified_phone when not approved" do
      allow(twilio_verification_result).to receive(:status).and_return(
        "pending",
      )

      patch phone_verification_path("1"), params: params

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({ "success" => false })
      expect(session_hash[:verified_phone]).to be_nil
    end

    it "redirects with an alert when Twilio returns 20404" do
      twilio_error = Twilio::REST::RestError.allocate
      allow(twilio_error).to receive(:code).and_return(20_404)
      allow(twilio_error).to receive(:message).and_return(
        "VerificationCheck was not found",
      )
      allow(twilio_verification_result).to receive(:status).and_raise(
        twilio_error,
      )

      patch phone_verification_path("1"), params: params

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(
        "SMS verification not found. Please try again.",
      )
    end

    it "re-raises unexpected Twilio errors" do
      twilio_error = Twilio::REST::RestError.allocate
      allow(twilio_error).to receive(:code).and_return(50_000)
      allow(twilio_error).to receive(:message).and_return("twilio unavailable")
      allow(twilio_verification_result).to receive(:status).and_raise(
        twilio_error,
      )

      expect do
        patch phone_verification_path("1"), params: params
      end.to raise_error(Twilio::REST::RestError)
    end

    it "does not create a user after verification" do
      expect do
        patch phone_verification_path("1"), params: params
      end.not_to change(User, :count)
    end

    it "sends Twilio verification check with expected phone and code" do
      patch phone_verification_path("1"), params: params

      expect(twilio_verification_checks_double).to have_received(:create).with(
        to: "+14105551212",
        code: "123456",
      )
    end

    context "when SKIP_PHONE_VERIFICATION is enabled" do
      around do |example|
        previous_values = {
          "SKIP_PHONE_VERIFICATION" => ENV["SKIP_PHONE_VERIFICATION"],
          "DEFAULT_USER_FULL_NAME" => ENV["DEFAULT_USER_FULL_NAME"],
          "DEFAULT_CITY" => ENV["DEFAULT_CITY"],
          "DEFAULT_REGION_CODE" => ENV["DEFAULT_REGION_CODE"],
          "DEFAULT_POSTAL_CODE" => ENV["DEFAULT_POSTAL_CODE"],
          "DEFAULT_STREET" => ENV["DEFAULT_STREET"],
          "DEFAULT_LATITUDE" => ENV["DEFAULT_LATITUDE"],
          "DEFAULT_LONGITUDE" => ENV["DEFAULT_LONGITUDE"],
        }

        ENV["SKIP_PHONE_VERIFICATION"] = "1"
        ENV["DEFAULT_USER_FULL_NAME"] = "Skip+Flow+User"
        ENV["DEFAULT_CITY"] = "Baltimore"
        ENV["DEFAULT_REGION_CODE"] = "MD"
        ENV["DEFAULT_POSTAL_CODE"] = "21224"
        ENV["DEFAULT_STREET"] = "123+Main+St"
        ENV["DEFAULT_LATITUDE"] = "39.2904"
        ENV["DEFAULT_LONGITUDE"] = "-76.6122"

        example.run
      ensure
        previous_values.each do |key, value|
          value.nil? ? ENV.delete(key) : ENV[key] = value
        end
      end

      it "sets verified_phone and applies default user/address side effects" do
        expect do
          patch phone_verification_path("1"), params: params
        end.to change(User, :count)
          .by(1)
          .and(change(Address, :count).by(1))
          .and(change(UserAddress, :count).by(1))

        user = User.find_by(phone: "4105551212")

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({ "success" => true })
        expect(session_hash[:verified_phone]).to eq("4105551212")
        expect(user).to have_attributes(
          is_admin: true,
          is_email_verified: true,
          is_phone_verified: true,
          is_registered_to_vote: true,
          is_registration_complete: true,
          registration_status: "completed",
        )
      end
    end
  end
end
