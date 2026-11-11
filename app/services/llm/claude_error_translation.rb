# frozen_string_literal: true

module Llm
  # @lat: [[lat.md/explanation/llm-summaries#Talking to the Anthropic SDK]]
  module ClaudeErrorTranslation
    MAX_TRANSLATED_ERROR_LENGTH = 200

    def self.translate
      yield
    rescue Anthropic::Errors::APITimeoutError => e
      raise Llm::TransportError, "claude transport: timeout (#{e.message.to_s[0, MAX_TRANSLATED_ERROR_LENGTH]})"
    rescue Anthropic::Errors::APIConnectionError => e
      raise Llm::TransportError, "claude transport: connection (#{e.message.to_s[0, MAX_TRANSLATED_ERROR_LENGTH]})"
    rescue Anthropic::Errors::RateLimitError
      raise Llm::TransportError, "claude transport: 429 rate_limit"
    rescue Anthropic::Errors::AuthenticationError
      raise Llm::TransportError, "claude transport: 401 authentication"
    # @lat: [[lat.md/explanation/llm-summaries#Talking to the Anthropic SDK#Why the rescue chain has an order]]
    rescue Anthropic::Errors::BadRequestError => e
      raise Llm::TransportError,
        "claude transport: #{e.status} #{e.class.name.demodulize.underscore} (#{e.message.to_s[0, MAX_TRANSLATED_ERROR_LENGTH]})"
    rescue Anthropic::Errors::APIStatusError => e
      raise Llm::TransportError, "claude transport: #{e.status} #{e.class.name.demodulize.underscore}"
    end
  end
end
