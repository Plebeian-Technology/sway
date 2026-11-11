# frozen_string_literal: true

module PipelineActivityLog
  # @lat: [[pipeline-activity-logger-overview#Why failure payloads cap error strings at 4000 characters]]
  class LlmJsonParseFailurePayload
    attr_reader :error_message, :raw_excerpt

    def initialize(error_message:, raw_excerpt:)
      @error_message = error_message.to_s
      @raw_excerpt = raw_excerpt.to_s
    end

    def to_h
      {
        error_message: error_message[0...4000] || "",
        raw_excerpt: raw_excerpt[0...4000] || ""
      }
    end
  end
end
