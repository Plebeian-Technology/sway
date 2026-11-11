# frozen_string_literal: true

module PipelineActivityLog
  # @lat: [[pipeline-activity-logger-overview#Why failure payloads cap error strings at 4000 characters]]
  class StageFailurePayload
    attr_reader :stage_name, :error_message

    def initialize(stage_name:, error_message:)
      @stage_name = stage_name.to_s
      @error_message = error_message.to_s
    end

    def to_h
      {
        stage_name: stage_name,
        error_message: error_message[0...4000] || ""
      }
    end
  end
end
