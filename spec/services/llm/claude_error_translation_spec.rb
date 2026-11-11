# frozen_string_literal: true

require "rails_helper"

# The one place Anthropic SDK exceptions become Sway's own taxonomy. Both the
# synchronous adapter and the batch service route through it, so a message
# asserted here is the message both paths emit.
RSpec.describe Llm::ClaudeErrorTranslation do
  def status_error(klass, status:, message: "boom")
    klass.new(
      url: URI("https://api.anthropic.com/v1/messages"),
      status: status,
      headers: {}, #: Hash[String, untyped]
      body: nil,
      request: nil,
      response: nil,
      message: message
    )
  end

  describe ".translate" do
    it "returns the block's value untouched when nothing raises" do
      expect(described_class.translate { :ok }).to eq(:ok)
    end

    it "translates APITimeoutError to Llm::TransportError 'timeout'" do
      expect {
        described_class.translate {
          raise Anthropic::Errors::APITimeoutError.new(url: URI("https://api.anthropic.com/v1/messages"), message: "took too long")
        }
      }.to raise_error(Llm::TransportError, /^claude transport: timeout \(took too long\)/)
    end

    it "translates APIConnectionError to Llm::TransportError 'connection'" do
      expect {
        described_class.translate {
          raise Anthropic::Errors::APIConnectionError.new(url: URI("https://api.anthropic.com/v1/messages"), message: "no route")
        }
      }.to raise_error(Llm::TransportError, /^claude transport: connection \(no route\)/)
    end

    it "translates RateLimitError to a fixed 429 message that leaks no upstream text" do
      expect {
        described_class.translate { raise status_error(Anthropic::Errors::RateLimitError, status: 429) }
      }.to raise_error(Llm::TransportError, "claude transport: 429 rate_limit")
    end

    it "translates AuthenticationError to a fixed 401 message that leaks no upstream text" do
      expect {
        described_class.translate { raise status_error(Anthropic::Errors::AuthenticationError, status: 401) }
      }.to raise_error(Llm::TransportError, "claude transport: 401 authentication")
    end

    it "translates any other APIStatusError to its status and demodulised class name" do
      expect {
        described_class.translate { raise status_error(Anthropic::Errors::InternalServerError, status: 500) }
      }.to raise_error(Llm::TransportError, /^claude transport: 500 internal_server_error/)
    end

    it "appends the upstream message to a BadRequestError translation, unlike other status errors" do
      expect {
        described_class.translate {
          raise status_error(
            Anthropic::Errors::BadRequestError, status: 400,
            message: "requests.0.custom_id: String should match pattern '^[a-zA-Z0-9_-]{1,64}$'"
          )
        }
      }.to raise_error(
        Llm::TransportError,
        "claude transport: 400 bad_request_error (requests.0.custom_id: String should match pattern '^[a-zA-Z0-9_-]{1,64}$')"
      )
    end

    it "truncates a long BadRequestError upstream message to MAX_TRANSLATED_ERROR_LENGTH" do
      expect {
        described_class.translate { raise status_error(Anthropic::Errors::BadRequestError, status: 400, message: "x" * 5000) }
      }.to raise_error(Llm::TransportError) { |e|
        expect(e.message).to include("x" * described_class::MAX_TRANSLATED_ERROR_LENGTH)
        expect(e.message).not_to include("x" * (described_class::MAX_TRANSLATED_ERROR_LENGTH + 1))
      }
    end

    it "still translates RateLimitError to the fixed 429 message with no upstream text, even though BadRequestError now carries detail" do
      expect {
        described_class.translate { raise status_error(Anthropic::Errors::RateLimitError, status: 429, message: "some upstream detail") }
      }.to raise_error(Llm::TransportError, "claude transport: 429 rate_limit")
    end

    it "still translates AuthenticationError to the fixed 401 message with no upstream text" do
      expect {
        described_class.translate { raise status_error(Anthropic::Errors::AuthenticationError, status: 401, message: "some upstream detail") }
      }.to raise_error(Llm::TransportError, "claude transport: 401 authentication")
    end

    it "rescues RateLimitError before the APIStatusError it subclasses" do
      expect(Anthropic::Errors::RateLimitError.ancestors).to include(Anthropic::Errors::APIStatusError)
      expect {
        described_class.translate { raise status_error(Anthropic::Errors::RateLimitError, status: 429) }
      }.to raise_error(Llm::TransportError, "claude transport: 429 rate_limit")
    end

    it "truncates a long upstream message to MAX_TRANSLATED_ERROR_LENGTH" do
      expect {
        described_class.translate {
          raise Anthropic::Errors::APITimeoutError.new(url: URI("https://api.anthropic.com/v1/messages"), message: "x" * 5000)
        }
      }.to raise_error(Llm::TransportError) { |e|
        expect(e.message.length).to be <= described_class::MAX_TRANSLATED_ERROR_LENGTH + 40
        expect(e.message).to include("x" * described_class::MAX_TRANSLATED_ERROR_LENGTH)
        expect(e.message).not_to include("x" * (described_class::MAX_TRANSLATED_ERROR_LENGTH + 1))
      }
    end

    it "lets a non-Anthropic error through unchanged, so a Sway bug is not disguised as transport" do
      expect {
        described_class.translate { raise ArgumentError, "programmer error" }
      }.to raise_error(ArgumentError, "programmer error")
    end

    it "lets an Llm::SchemaError raised inside the block through unchanged" do
      expect {
        described_class.translate { raise Llm::SchemaError, "claude schema: bad payload" }
      }.to raise_error(Llm::SchemaError, "claude schema: bad payload")
    end
  end
end
