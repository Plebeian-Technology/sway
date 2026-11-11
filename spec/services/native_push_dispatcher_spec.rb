# frozen_string_literal: true

require "rails_helper"

RSpec.describe NativePushDispatcher do
  let(:user) { create(:user) }
  let(:android_device) do
    create(:user_device, user: user, platform: "android", push_token: "fcm-token")
  end
  let(:ios_device) do
    create(:user_device, user: user, platform: "ios", push_token: "apns-token")
  end
  let(:payload) { {title: "T", body: "B", data: {bill_id: 1}} }

  describe ".send" do
    it "routes android to FcmClient" do
      expect(FcmClient).to receive(:deliver).with(
        push_token: "fcm-token", title: "T", body: "B", data: {bill_id: 1}
      ).and_return(true)
      described_class.deliver(android_device, payload)
    end

    it "routes ios to ApnsClient" do
      expect(ApnsClient).to receive(:deliver).with(
        device_token: "apns-token", title: "T", body: "B", data: {bill_id: 1}
      ).and_return(true)
      described_class.deliver(ios_device, payload)
    end

    it "raises ArgumentError on unknown platform" do
      bad = build_stubbed(:user_device, platform: "windows")
      expect { described_class.deliver(bad, payload) }.to raise_error(ArgumentError, /unknown platform/)
    end

    it "wraps FcmClient::DeviceNotRegisteredError" do
      allow(FcmClient).to receive(:deliver).and_raise(FcmClient::DeviceNotRegisteredError)
      expect {
        described_class.deliver(android_device, payload)
      }.to raise_error(NativePushDispatcher::DeviceNotRegisteredError)
    end

    it "wraps ApnsClient::DeviceNotRegisteredError" do
      allow(ApnsClient).to receive(:deliver).and_raise(ApnsClient::DeviceNotRegisteredError)
      expect {
        described_class.deliver(ios_device, payload)
      }.to raise_error(NativePushDispatcher::DeviceNotRegisteredError)
    end
  end
end
