require "rails_helper"

RSpec.describe Authentication, type: :controller do
  include_context "TwilioDouble"

  controller(ApplicationController) do
    def authenticate_sway_user!
    end

    def index
      head :ok
    end
  end

  before do
    controller.class.include(Authentication)
    routes.draw { get :index, to: "anonymous#index" }
  end

  describe "#send_phone_verification" do
    let(:session_store) { {existing: "value"} }
    let(:phone) { "(410) 555-1212" }

    context "when the skip switch is on" do
      around do |example|
        with_app_config(:dev_login, skip_phone_verification: true) { example.run }
      end

      it "stores the normalized phone and bypasses Twilio" do
        result = controller.send(:send_phone_verification, session_store, phone)

        expect(result).to be(true)
        expect(session_store[:phone]).to eq("4105551212")
        expect(twilio_verifications_double).not_to have_received(:create)
      end
    end

    context "when the skip switch is off" do
      around do |example|
        with_app_config(:dev_login, skip_phone_verification: false) { example.run }
      end

      it "sends an sms verification through Twilio" do
        result = controller.send(:send_phone_verification, session_store, phone)

        expect(result).to be(true)
        expect(session_store[:phone]).to eq("4105551212")
        expect(twilio_verifications_double).to have_received(:create).with(
          to: "+14105551212",
          channel: "sms"
        )
      end

      it "returns false and logs only safe fields (no recipient phone) when Twilio raises" do
        twilio_error = Twilio::REST::RestError.allocate
        allow(twilio_error).to receive(:code).and_return(60_200)
        # A raw Twilio RestError message contains the recipient's phone number.
        # The log must record only the event name and the error code, never the
        # phone.
        allow(twilio_error).to receive(:full_message).and_return(
          "The 'To' number +14105551212 is not a valid phone number."
        )
        allow(twilio_verifications_double).to receive(:create).and_raise(
          twilio_error
        )
        logged = [] #: Array[String]
        allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }

        result = controller.send(:send_phone_verification, session_store, phone)

        expect(result).to be(false)
        expect(logged.join("\n")).to include("authentication.phone_verification_failed")
        expect(logged.join("\n")).not_to include("4105551212")
      end
    end

    it "returns false when session or phone is missing" do
      expect(controller.send(:send_phone_verification, nil, phone)).to be(false)
      expect(
        controller.send(:send_phone_verification, session_store, nil)
      ).to be(false)
    end
  end
end
