# frozen_string_literal: true

require "anthropic"

module Llm
  # @lat: [[lat.md/explanation/llm-summaries#Talking to the Anthropic SDK]]
  module ClaudeConnection
    DEFAULT_MAX_RETRIES = 2

    DEFAULT_TIMEOUT_SECONDS = 120

    # @lat: [[lat.md/explanation/llm-summaries#Batch summarisation#Sizing the results-read timeout]]
    BATCH_RESULTS_TIMEOUT_SECONDS = 600

    def self.build
      Anthropic::Client.new(
        api_key: api_key,
        max_retries: DEFAULT_MAX_RETRIES,
        timeout: DEFAULT_TIMEOUT_SECONDS.to_f
      )
    end

    def self.api_key
      EnvSecret.read("ANTHROPIC_API_KEY") || raise(
        Llm::TransportError,
        "claude transport: ANTHROPIC_API_KEY is not set (or is blank) in this process's environment"
      )
    end
    private_class_method :api_key
  end
end
