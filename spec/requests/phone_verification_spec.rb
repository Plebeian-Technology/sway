require "rails_helper"

RSpec.describe "PhoneVerification", type: :request do
  include_context "SessionDouble"
  include_context "TwilioDouble"

  describe "POST /phone_verification" do
    let(:params) { {phone_verification: {phone: "(410) 555-1212"}} }

    context "when the skip switch is on" do
      around do |example|
        with_app_config(:dev_login, skip_phone_verification: true) { example.run }
      end

      it "stores normalized phone in session and returns success" do
        post phone_verification_index_path, params: params

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({"success" => true})
        expect(session_hash[:phone]).to eq("4105551212")
      end

      it "returns 422 when phone is not 10 digits" do
        post phone_verification_index_path, params: {phone_verification: {phone: "123"}}

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["success"]).to be(false)
      end
    end

    context "when the skip switch is off" do
      around do |example|
        with_app_config(:dev_login, skip_phone_verification: false) { example.run }
      end

      it "sends a Twilio verification and returns success" do
        post phone_verification_index_path, params: params

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({"success" => true})
        expect(session_hash[:phone]).to eq("4105551212")
      end

      it "returns false when Twilio raises an error" do
        allow_any_instance_of(PhoneVerificationController).to receive(
          :send_phone_verification
        ).and_return(false)

        post phone_verification_index_path, params: params

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({"success" => false})
      end
    end
  end

  describe "PATCH /phone_verification/:id" do
    let(:params) { {phone_verification: {code: "123456"}} }

    around do |example|
      with_app_config(:dev_login, skip_phone_verification: false) { example.run }
    end

    before { session_hash[:phone] = "4105551212" }

    let(:verification_not_found_error) do
      twilio_error = Twilio::REST::RestError.allocate
      allow(twilio_error).to receive(:code).and_return(20_404)
      leaky_message = "VerificationCheck was not found for recipient +14105551212"
      allow(twilio_error).to receive(:message).and_return(leaky_message)
      allow(twilio_error).to receive(:full_message).and_return(leaky_message)
      twilio_error
    end

    it "stores verified_phone and returns success when approved" do
      patch phone_verification_path("1"), params: params

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({"success" => true})
      expect(session_hash[:verified_phone]).to eq("4105551212")
    end

    it "returns 422 when session phone or code is blank or invalid" do
      session_hash[:phone] = nil
      patch phone_verification_path("1"), params: params
      expect(response).to have_http_status(:unprocessable_content)

      session_hash[:phone] = "4105551212"
      patch phone_verification_path("1"), params: {phone_verification: {code: "   "}}
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns false and does not store verified_phone when not approved" do
      allow(twilio_verification_result).to receive(:status).and_return(
        "pending"
      )

      patch phone_verification_path("1"), params: params

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({"success" => false})
      expect(session_hash[:verified_phone]).to be_nil
    end

    # @lat: [[identity-and-access#Identity and access#The phone number is the account#A verification-not-found reply has one safe browser outcome]]
    it "returns the fixed failure JSON on XHR when Twilio returns 20404" do
      allow(twilio_verification_result).to receive(:status).and_raise(
        verification_not_found_error
      )

      patch phone_verification_path("1"),
        params: params,
        headers: {"X-Requested-With" => "XMLHttpRequest"}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        {"success" => false, "error" => "Code not found."}
      )
      expect(response.body).not_to include("4105551212")
      expect(response.body).not_to include("+14105551212")
      expect(session_hash[:verified_phone]).to be_nil
    end

    # @lat: [[identity-and-access#Identity and access#The phone number is the account#A verification-not-found reply has one safe browser outcome]]
    it "returns the same fixed failure JSON to a plain request when Twilio returns 20404" do
      allow(twilio_verification_result).to receive(:status).and_raise(
        verification_not_found_error
      )

      patch phone_verification_path("1"), params: params

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        {"success" => false, "error" => "Code not found."}
      )
      expect(response.body).not_to include("4105551212")
      expect(response.body).not_to include("+14105551212")
      expect(session_hash[:verified_phone]).to be_nil
    end

    # @lat: [[twilio-error-phone-redaction#Why Twilio error handling redacts recipient identifiers]]
    it "raises a sanitized error carrying no recipient phone on unexpected Twilio errors" do
      twilio_error = Twilio::REST::RestError.allocate
      allow(twilio_error).to receive(:code).and_return(50_000)
      allow(twilio_error).to receive(:status_code).and_return(500)
      leaky = "The 'To' number +14105551212 is not a valid phone number."
      allow(twilio_error).to receive(:message).and_return(leaky)
      allow(twilio_error).to receive(:full_message).and_return(leaky)
      allow(twilio_verification_result).to receive(:status).and_raise(twilio_error)

      logged = [] #: Array[String]
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }

      raised = nil #: Authentication::TwilioVerificationError?
      expect do
        patch phone_verification_path("1"), params: params
      end.to raise_error(Authentication::TwilioVerificationError) { |e| raised = e }

      # The `&.` keeps the type checker happy, since `raised` may be nil. If it
      # were nil the message would be empty, so the include below would fail
      # rather than pass on a technicality.
      expect(raised&.message.to_s).to include("code=50000")
      expect(raised&.message.to_s).not_to include("4105551212")
      expect(raised&.cause).to be_nil
      expect(logged.join("\n")).not_to include("4105551212")
    end

    it "answers a fixed retry message when Twilio cannot be reached" do
      allow(twilio_verification_checks_double).to receive(:create).and_raise(
        Twilio::REST::TwilioError.new("execution expired +14105551212")
      )
      logged = [] #: Array[String]
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }

      patch phone_verification_path("1"), params: params

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        {"success" => false, "error" => "Could not check the code. Please try again."}
      )
      expect(response.body).not_to include("4105551212")
      expect(logged.join("\n")).to include("phone_verification.update_failed")
      expect(logged.join("\n")).not_to include("4105551212")
      expect(session_hash[:verified_phone]).to be_nil
    end

    context "when the session phone is already verified" do
      it "returns success without calling Twilio when the session phone is already verified" do
        patch phone_verification_path("1"), params: params
        expect(session_hash[:verified_phone]).to eq("4105551212")

        allow(twilio_verification_checks_double).to receive(:create).and_raise(verification_not_found_error)
        patch phone_verification_path("1"), params: params

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({"success" => true})
        expect(session_hash[:verified_phone]).to eq("4105551212")
        expect(twilio_verification_checks_double).to have_received(:create).once
      end

      it "still calls Twilio for a different session phone and does not mark it verified unless approved" do
        session_hash[:verified_phone] = "4105551212"
        session_hash[:phone] = "4105550000"
        allow(twilio_verification_result).to receive(:status).and_return("pending")

        patch phone_verification_path("1"), params: params

        expect(response.parsed_body).to eq({"success" => false})
        expect(twilio_verification_checks_double).to have_received(:create).with(to: "+14105550000", code: "123456")
        expect(session_hash[:verified_phone]).to eq("4105551212")
      end

      it "still returns 422 for a blank code" do
        session_hash[:verified_phone] = "4105551212"

        patch phone_verification_path("1"), params: {phone_verification: {code: "   "}}

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "still returns 422 when the session has no phone" do
        session_hash[:verified_phone] = "4105551212"
        session_hash[:phone] = nil

        patch phone_verification_path("1"), params: params

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "calls Twilio for a never-verified session phone and leaves verified_phone nil when pending" do
      allow(twilio_verification_result).to receive(:status).and_return("pending")

      patch phone_verification_path("1"), params: params

      expect(twilio_verification_checks_double).to have_received(:create).once
      expect(session_hash[:verified_phone]).to be_nil
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
        code: "123456"
      )
    end

    it "strips surrounding whitespace from code before calling Twilio verification" do
      patch phone_verification_path("1"), params: {phone_verification: {code: " 123456 "}}

      expect(response).to have_http_status(:ok)
      expect(twilio_verification_checks_double).to have_received(:create).with(
        to: "+14105551212",
        code: "123456"
      )
    end

    context "rate limiting on #update" do
      it "throttles after 5 code checks for the same session phone within 10 minutes" do
        with_rate_limit_enabled(:phone_verify) do
          allow(twilio_verification_result).to receive(:status).and_return("pending")

          6.times do |i|
            patch phone_verification_path("1"),
              params: params,
              headers: {"REMOTE_ADDR" => "10.0.1.#{i + 1}"},
              as: :json
          end

          expect(response).to have_http_status(:too_many_requests)
        end
      end

      it "throttles after 10 code checks from the same IP within 1 minute" do
        with_rate_limit_enabled(:phone_verify) do
          allow(twilio_verification_result).to receive(:status).and_return("pending")

          11.times do |i|
            session_hash[:phone] = "410555#{i.to_s.rjust(4, "0")}"
            patch phone_verification_path("1"),
              params: params,
              headers: {"REMOTE_ADDR" => "10.0.2.1"},
              as: :json
          end

          expect(response).to have_http_status(:too_many_requests)
        end
      end
    end

    context "when the skip switch is on" do
      around do |example|
        with_app_config(
          :dev_login,
          skip_phone_verification: true,
          dev_account_full_name: "Skip+Flow+User",
          dev_account_sway_locale: "baltimore-maryland-united_states"
        ) { example.run }
      end

      before { create(:sway_locale, :baltimore) }

      it "verifies the phone without claiming Sway registration" do
        expect do
          patch phone_verification_path("1"), params: params
        end.to change(User, :count)
          .by(1)
          .and(change(Address, :count).by(1))
          .and(change(UserAddress, :count).by(1))

        user = User.find_by(phone: "4105551212") #: User

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({"success" => true})
        expect(session_hash[:verified_phone]).to eq("4105551212")
        # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address#The bypass skips SMS, not address registration]]
        expect(user).to have_attributes(
          is_email_verified: true,
          is_phone_verified: true,
          is_registered_to_vote: true,
          is_registration_complete: false,
          registration_status: "pending"
        )
        expect(user.registered?).to be(false)
        expect(user.user_legislators.where(active: true)).to be_empty

        # @lat: [[identity-and-access#The phone number is the account#Enrollment attributes exclude admin privileges]]
        stub_const("User::ADMIN_PHONES", ["4109999999"])
        expect(user.is_sway_admin?).to be(false)
      end
    end
  end
end
