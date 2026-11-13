# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sway::TwilioClient do
  describe ".build" do
    it "constructs a Twilio::REST::Client from the TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN env" do
      fake_client = instance_double(Twilio::REST::Client)
      allow(Twilio::REST::Client).to receive(:new).and_return(fake_client)

      expect(described_class.build).to eq(fake_client)
      expect(Twilio::REST::Client).to have_received(:new)
        .with(ENV["TWILIO_ACCOUNT_SID"], ENV["TWILIO_AUTH_TOKEN"], nil, nil, an_instance_of(Twilio::HTTP::Client))
    end

    # @lat: [[twilio-error-phone-redaction#Why a Twilio network failure is answered, not raised]]
    it "gives the client a 10 second HTTP timeout" do
      expect(described_class.build.http_client.timeout).to eq(10)
    end
  end

  # @lat: [[sms-notification-service-design#Where the displayed Sway number comes from]]
  describe ".display_from_phone" do
    it "formats an E.164 North American sending number for people to read" do
      with_env("TWILIO_FROM_PHONE" => "+14105550123") do
        expect(described_class.display_from_phone).to eq("(410) 555-0123")
      end
    end

    it "accepts a ten-digit number with no country code" do
      with_env("TWILIO_FROM_PHONE" => "410-555-0123\n") do
        expect(described_class.display_from_phone).to eq("(410) 555-0123")
      end
    end

    it "returns nil when the sending number is unset" do
      with_env("TWILIO_FROM_PHONE" => nil) do
        expect(described_class.display_from_phone).to be_nil
      end
    end

    it "returns nil rather than a half-formatted value for a number it cannot format" do
      with_env("TWILIO_FROM_PHONE" => "+442071838750") do
        expect(described_class.display_from_phone).to be_nil
      end
    end
  end
end
