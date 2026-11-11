# frozen_string_literal: true

module PipelineActivityLog
  # @lat: [[pipeline-activity-logger-overview#Why failure payloads cap error strings at 4000 characters]]
  class LlmProviderErrorPayload
    attr_reader :error_message

    def initialize(error_message:)
      @error_message = error_message.to_s
    end

    def to_h
      {
        error_message: error_message[0...4000] || ""
      }
    end
  end
end
