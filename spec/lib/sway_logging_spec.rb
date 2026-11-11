# frozen_string_literal: true

require "rails_helper"

# @lat: [[sway-logging-design#Why .summarize's Hash branch redacts at every nesting level]]
RSpec.describe SwayLogging do
  describe ".summarize" do
    it "redacts sensitive keys (to, body, phone) at the top level" do
      result = described_class.summarize({to: "+14105551234", body: "secret text", other: "keep"})

      expect(result["to"]).to eq("[FILTERED]")
      expect(result["body"]).to eq("[FILTERED]")
      expect(result["other"]).to eq("keep")
    end

    it "redacts sensitive keys at nested levels" do
      result = described_class.summarize({args: {phone: "+14105551234", note: "keep"}})

      expect(result["args"]["phone"]).to eq("[FILTERED]")
      expect(result["args"]["note"]).to eq("keep")
    end

    it "redacts suffix and pattern-matched sensitive keys in both summarize and sanitize_value" do
      result = described_class.summarize({
        from: "+14105550000",
        api_key: "secret-key",
        push_token: "tok-123",
        client_secret: "shh",
        phone_number: "+14105551234",
        user_email: "voter@example.com",
        street: "123 Main St",
        postal_code: "21201",
        latitude: 39.29,
        longitude: -76.61
      })

      expect(result.values).to all(eq("[FILTERED]"))
      expect(described_class.sanitize_value(:push_token, "tok-123")).to eq("[FILTERED]")
      expect(described_class.sanitize_value(:full_name, "Jane Voter")).to eq("[FILTERED]")
    end
  end

  describe "lograge custom_options" do
    it "scrubs exception_message for PII and Anthropic API keys" do
      event = ActiveSupport::Notifications::Event.new(
        "process_action.action_controller",
        Time.current,
        Time.current,
        "1",
        {
          request_id: "req-1",
          exception: ["RuntimeError", "Failed for voter@example.com with key sk-ant-api03-secretkeyvalue12345"]
        }
      )

      config = Rails.application.config #: untyped
      options = config.lograge.custom_options.call(event)

      expect(options[:exception_class]).to eq("RuntimeError")
      expect(options[:exception_message]).not_to include("voter@example.com")
      expect(options[:exception_message]).not_to include("sk-ant-api03-secretkeyvalue12345")
      expect(options[:exception_message]).to include("[FILTERED_EMAIL]")
      expect(options[:exception_message]).to include("[FILTERED_KEY]")
    end
  end
end
