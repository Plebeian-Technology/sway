# frozen_string_literal: true

require "rails_helper"

RSpec.describe FcmClient do
  let(:project_id) { "sway-fcm-test" }
  let(:service_account_json) do
    {
      type: "service_account",
      project_id: project_id,
      private_key_id: "abc123",
      private_key: <<~PEM,
        -----BEGIN PRIVATE KEY-----
        MIIBVAIBADANBgkqhkiG9w0BAQEFAASCAT4wggE6AgEAAkEAyOlRkr4l5Z6Q3vQs
        XvY1eOqSqHvc6Lh3v2ulSeVYGxYZ1dQXvDM2Y8kQ0O4Ynjc8wBmZbZpOvL7v3K0p
        gQUOawIDAQABAkAfFNTKKa7c1g5nVFfhjPWHsiUz3hI7YRGvLp1Z+v5JmVL0Y5xT
        mE6qJFEXhqv9oJ8ya1B9GScEMfwTmKpc/PLJAiEA/BX5LL9jXl3xSj7w5w3pT9oC
        7C7dVOyB0uBC2ZPRZuMCIQDLcTAwjvvqwk0n4uRVGqcFc9dE+f/jCVE1m2GjN1Lr
        eQIgcrtg0wHQU6c/L/1Cjz4fY0BGsoY9k7ks8lOq9G/tvI0CIE0VJa/v1Y3NtTNS
        0K+Zl+l1Z9rTl6ZdEszKf4f6Z4uxAiArNJNu5VHMvB0v7VtJIYnFZ1kV+M+Ji8Yk
        CbB4MCJWWA==
        -----END PRIVATE KEY-----
      PEM
      client_email: "fcm@#{project_id}.iam.gserviceaccount.com",
      client_id: "1",
      auth_uri: "https://accounts.google.com/o/oauth2/auth",
      token_uri: "https://oauth2.googleapis.com/token"
    }.to_json
  end

  before do
    Rails.cache.clear
    Rails.application.config.fcm = ActiveSupport::OrderedOptions.new.tap do |c|
      c.project_id = project_id
      c.service_account_json = service_account_json
      c.enabled = true
    end
    allow(described_class).to receive(:oauth2_token).and_return("fake-bearer")
  end

  describe ".send" do
    let(:fcm_url) { "https://fcm.googleapis.com/v1/projects/#{project_id}/messages:send" }

    it "POSTs FCM v1 messages:send with bearer auth" do
      stub = stub_request(:post, fcm_url)
        .with(headers: {"Authorization" => "Bearer fake-bearer"})
        .to_return(status: 200, body: {name: "projects/x/messages/123"}.to_json)

      result = described_class.deliver(push_token: "device-token", title: "T", body: "B", data: {bill_id: 1})
      expect(stub).to have_been_requested
      expect(result["name"]).to include("messages/123")
    end

    it "raises DeviceNotRegisteredError on UNREGISTERED" do
      stub_request(:post, fcm_url).to_return(
        status: 404,
        body: {error: {status: "NOT_FOUND", details: [{errorCode: "UNREGISTERED"}]}}.to_json
      )
      expect {
        described_class.deliver(push_token: "stale", title: "T", body: "B")
      }.to raise_error(FcmClient::DeviceNotRegisteredError)
    end

    it "raises FcmError on other failures" do
      stub_request(:post, fcm_url).to_return(
        status: 500,
        body: {error: {status: "INTERNAL"}}.to_json
      )
      expect {
        described_class.deliver(push_token: "x", title: "T", body: "B")
      }.to raise_error(FcmClient::FcmError, /INTERNAL/)
    end

    it "returns nil when fcm not enabled" do
      Rails.application.config.fcm.enabled = false
      expect(described_class.deliver(push_token: "x", title: "T", body: "B")).to be_nil
    end

    # The OAuth bearer token stays in memory only, never Rails.cache, which is
    # disk-backed on the production Pi. FCM HTTP calls must also set their
    # own timeouts.
    context "OAuth token handling" do
      around do |ex|
        original = Rails.cache
        begin
          Rails.cache = ActiveSupport::Cache::MemoryStore.new
          ex.run
        ensure
          Rails.cache = original
        end
      end

      before do
        require "googleauth"
        FcmClient.instance_variable_set(:@oauth2_token, nil)
        FcmClient.instance_variable_set(:@cached_until, nil)
        # Run the real caching code here; the outer before block replaces
        # oauth2_token completely.
        allow(described_class).to receive(:oauth2_token).and_call_original
        creds = double("ServiceAccountCredentials", fetch_access_token!: {"access_token" => "fake-bearer"})
        allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(creds)
        stub_request(:post, fcm_url).to_return(status: 200, body: {name: "projects/x/messages/1"}.to_json)
      end

      after do
        FcmClient.instance_variable_set(:@oauth2_token, nil)
        FcmClient.instance_variable_set(:@cached_until, nil)
      end

      it "keeps the OAuth bearer off Rails.cache (in-process memo only)" do
        described_class.deliver(push_token: "t", title: "T", body: "B")

        # The old code called Rails.cache.fetch, which left the live token here.
        expect(Rails.cache.read("fcm:oauth2_token")).to be_nil
      end

      it "fetches the bearer once across multiple sends (memoized)" do
        described_class.deliver(push_token: "t", title: "T", body: "B")
        described_class.deliver(push_token: "t", title: "T", body: "B")

        expect(Google::Auth::ServiceAccountCredentials).to have_received(:make_creds).once
      end

      it "passes explicit open/read timeouts to Net::HTTP.start" do
        allow(described_class).to receive(:oauth2_token).and_return("fake-bearer")
        expect(Net::HTTP).to receive(:start).with(
          anything, anything, hash_including(open_timeout: 5, read_timeout: 10)
        ).and_call_original

        described_class.deliver(push_token: "t", title: "T", body: "B")
      end
    end
  end
end
