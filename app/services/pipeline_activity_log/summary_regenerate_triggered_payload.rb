# frozen_string_literal: true

module PipelineActivityLog
  # @lat: [[pipeline-activity-log-summary-regenerate-event#Why one event covers "generate" and "regenerate"]]
  class SummaryRegenerateTriggeredPayload
    attr_reader :bill_external_id, :bill_id, :first_generation

    def initialize(bill_external_id:, bill_id:, first_generation:)
      @bill_external_id = bill_external_id.to_s
      @bill_id = bill_id.to_i
      @first_generation = !!first_generation
    end

    def to_h
      {
        bill_external_id: bill_external_id,
        bill_id: bill_id,
        first_generation: first_generation
      }
    end
  end
end
