# frozen_string_literal: true

# @lat: [[run-legislation-pipeline-job-internals#Why run_run_level_stage rewraps a stray BillProcessingError-shaped failure as StageError]]
class StageError < StandardError; end
