require "rails_helper"

RSpec.describe Authentication, type: :controller do
  include_context "TwilioDouble"

  controller(ApplicationController) do
    include Authentication

    skip_before_action :authenticate_sway_user!

    def index
      head :ok
    end
  end

  before { routes.draw { get "index" => "anonymous#index" } }

  describe "#send_phone_verification" do
    let(:session_store) { { existing: "value" } }
    let(:phone) { "(410) 555-1212" }

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

      it "stores the normalized phone and bypasses Twilio" do
        result = controller.send(:send_phone_verification, session_store, phone)

        expect(result).to be(true)
        expect(session_store[:phone]).to eq("4105551212")
        expect(twilio_verifications_double).not_to have_received(:create)
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

      it "sends an sms verification through Twilio" do
        result = controller.send(:send_phone_verification, session_store, phone)

        expect(result).to be(true)
        expect(session_store[:phone]).to eq("4105551212")
        expect(twilio_verifications_double).to have_received(:create).with(
          to: "+14105551212",
          channel: "sms",
        )
      end

      it "returns false and reports the error when Twilio raises" do
        twilio_error = Twilio::REST::RestError.allocate
        allow(twilio_error).to receive(:full_message).and_return(
          "twilio failure",
        )
        allow(twilio_verifications_double).to receive(:create).and_raise(
          twilio_error,
        )
        allow(Rails.logger).to receive(:error)

        result = controller.send(:send_phone_verification, session_store, phone)

        expect(result).to be(false)
        expect(Rails.logger).to have_received(:error).with("twilio failure")
      end
    end

    it "returns false when session or phone is missing" do
      expect(controller.send(:send_phone_verification, nil, phone)).to be(false)
      expect(
        controller.send(:send_phone_verification, session_store, nil),
      ).to be(false)
    end
  end

  describe "private helpers" do
    describe "#verified?" do
      it "returns true when @user has a verified phone" do
        controller.instance_variable_set(
          :@user,
          build(:user, is_phone_verified: true),
        )

        expect(controller.send(:verified?)).to be(true)
      end

      it "returns nil when @user is not set" do
        controller.instance_variable_set(:@user, nil)

        expect(controller.send(:verified?)).to be_nil
      end
    end

    describe "#passkey?" do
      it "returns false when user has no passkeys" do
        user = create(:user)
        controller.instance_variable_set(:@user, user)

        expect(controller.send(:passkey?)).to be(false)
      end

      it "returns true when user has one or more passkeys" do
        user = create(:user)
        create(:passkey, user: user)
        controller.instance_variable_set(:@user, user)

        expect(controller.send(:passkey?)).to be(true)
      end
    end

    describe "#find_by_phone" do
      it "memoizes the first lookup result" do
        first_user = create(:user, phone: "4105556000")
        second_user = create(:user, phone: "4105556001")

        allow(User).to receive(:find_by).and_return(first_user, second_user)

        first_lookup = controller.send(:find_by_phone, "4105556000")
        second_lookup = controller.send(:find_by_phone, "4105556001")

        expect(first_lookup).to eq(first_user)
        expect(second_lookup).to eq(first_user)
        expect(User).to have_received(:find_by).once.with(phone: "4105556000")
      end
    end
  end
end
