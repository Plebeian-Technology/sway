# frozen_string_literal: true

module PipelineActivityLog
  # @lat: [[pipeline-activity-logger-overview#Why failure payloads cap error strings at 4000 characters]]
  class IngestionFailurePayload
    attr_reader :bill_external_id, :error_message

    def initialize(bill_external_id:, error_message:)
      @bill_external_id = bill_external_id.to_s
      @error_message = error_message.to_s
    end

    def to_h
      {
        bill_external_id: bill_external_id,
        error_message: error_message[0...4000] || ""
      }
    end
  end
end
