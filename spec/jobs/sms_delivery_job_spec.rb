# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmsDeliveryJob, type: :job do
  describe "#perform" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TWILIO_ACCOUNT_SID").and_return("AC123")
      allow(ENV).to receive(:[]).with("TWILIO_AUTH_TOKEN").and_return("token")
      allow(ENV).to receive(:[]).with("TWILIO_FROM_PHONE").and_return("9876543210")
    end

    it "sends SMS via Twilio" do
      client = instance_double(Twilio::REST::Client)
      messages = instance_double(Twilio::REST::Api::V2010::AccountContext::MessageList)

      allow(Twilio::REST::Client).to receive(:new).and_return(client)
      allow(client).to receive(:messages).and_return(messages)

      expect(messages).to receive(:create).with(
        from: "9876543210",
        to: "1234567890",
        body: "Hello"
      )

      described_class.new.perform(to: "1234567890", body: "Hello")
    end
  end
end
