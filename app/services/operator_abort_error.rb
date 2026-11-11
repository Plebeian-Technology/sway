# frozen_string_literal: true

# @lat: [[pipeline-run-failure-handling#Why OperatorAbortError bypasses handle_run_failure entirely]]
class OperatorAbortError < StandardError
  attr_reader :stage, :processed_count, :terminal_status

  def initialize(stage:, processed_count:, terminal_status:)
    @stage = stage
    @processed_count = processed_count
    @terminal_status = terminal_status
    super("operator aborted run (status=#{terminal_status}) during stage #{stage} after #{processed_count} bills")
  end
end
