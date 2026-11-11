# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApnsClient do
  before do
    Rails.application.config.apns = ActiveSupport::OrderedOptions.new.tap do |c|
      c.auth_key_p8 = "-----BEGIN PRIVATE KEY-----\nFAKE\n-----END PRIVATE KEY-----"
      c.key_id = "ABC123"
      c.team_id = "ABCDE12345"
      c.bundle_id = "app.example.test"
      c.env = "development"
      c.enabled = true
    end
    Thread.current[:apns_pool_instance] = nil
  end

  let(:fake_pool) { instance_double("Apnotic::ConnectionPool") }
  let(:fake_connection) { instance_double("Apnotic::Connection") }

  before do
    allow(described_class).to receive(:build_connection_pool).and_return(fake_pool)
    allow(fake_pool).to receive(:with).and_yield(fake_connection)
  end

  describe ".send" do
    it "returns true on APNs 200 response" do
      response = double(ok?: true)
      allow(fake_connection).to receive(:push).and_return(response)
      result = described_class.deliver(device_token: "abc", title: "T", body: "B", data: {kind: "x"})
      expect(result).to be(true)
    end

    it "raises DeviceNotRegisteredError on Unregistered (410)" do
      response = double(ok?: false, status: 410, body: {reason: "Unregistered"}.to_json)
      allow(fake_connection).to receive(:push).and_return(response)
      expect {
        described_class.deliver(device_token: "abc", title: "T", body: "B")
      }.to raise_error(ApnsClient::DeviceNotRegisteredError)
    end

    it "raises DeviceNotRegisteredError on BadDeviceToken (400)" do
      response = double(ok?: false, status: 400, body: {reason: "BadDeviceToken"}.to_json)
      allow(fake_connection).to receive(:push).and_return(response)
      expect {
        described_class.deliver(device_token: "abc", title: "T", body: "B")
      }.to raise_error(ApnsClient::DeviceNotRegisteredError)
    end

    it "raises ApnsError on other non-2xx" do
      response = double(ok?: false, status: 500, body: {reason: "InternalServerError"}.to_json)
      allow(fake_connection).to receive(:push).and_return(response)
      expect {
        described_class.deliver(device_token: "abc", title: "T", body: "B")
      }.to raise_error(ApnsClient::ApnsError, /500/)
    end

    it "raises ApnsError on nil (timeout) response" do
      allow(fake_connection).to receive(:push).and_return(nil)
      expect {
        described_class.deliver(device_token: "abc", title: "T", body: "B")
      }.to raise_error(ApnsClient::ApnsError, /timeout/)
    end

    it "returns nil when apns not enabled" do
      Rails.application.config.apns.enabled = false
      expect(described_class.deliver(device_token: "x", title: "T", body: "B")).to be_nil
    end
  end

  describe ".build_connection_pool" do
    it "builds a pool of size 1 per thread so a shared StringIO is not read after EOF" do
      allow(described_class).to receive(:build_connection_pool).and_call_original
      allow(Apnotic::ConnectionPool).to receive(:new).and_return(fake_pool)

      described_class.build_connection_pool(Rails.application.config.apns)

      expect(Apnotic::ConnectionPool).to have_received(:new).with(
        hash_including(
          auth_method: :token,
          cert_path: an_instance_of(StringIO),
          key_id: "ABC123",
          team_id: "ABCDE12345"
        ),
        size: 1
      )
    end
  end
end
