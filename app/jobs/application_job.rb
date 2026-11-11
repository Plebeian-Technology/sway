# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  around_perform :log_job_execution

  # @lat: [[application-job-discard-on-deserialization#Why ApplicationJob discards ActiveJob::DeserializationError]]
  discard_on ActiveJob::DeserializationError

  private

  def log_job_execution
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) #: Float

    SwayLogging.info(
      "job_start",
      job_class: self.class.name,
      job_id: job_id,
      queue: queue_name,
      arguments: SwayLogging.summarize(arguments),
      executions: executions
    )

    yield

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC) #: Float
    duration_ms = ((now - started_at) * 1000).round(1)

    SwayLogging.info(
      "job_finish",
      job_class: self.class.name,
      job_id: job_id,
      queue: queue_name,
      duration_ms: duration_ms,
      executions: executions
    )
  rescue => e
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC) #: Float
    duration_ms = ((now - (started_at || now)) * 1000).round(1)

    SwayLogging.log_exception(
      "job_fail",
      exception: e,
      job_class: self.class.name,
      job_id: job_id,
      queue: queue_name,
      duration_ms: duration_ms,
      executions: executions,
      arguments: SwayLogging.summarize(arguments)
    )
    raise
  end
end
