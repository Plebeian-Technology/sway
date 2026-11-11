# frozen_string_literal: true

# @lat: [[boot-step-error-reporting#Where the report goes]]
class BootStep
  # @lat: [[boot-step-error-reporting#Why BootStep rescues Exception and swallows reporting errors]]
  def self.run(name)
    yield
  rescue Exception => e # rubocop:disable Lint/RescueException
    report(name, e)
    raise
  end

  # @lat: [[boot-step-error-reporting#Why .report is safe to call even when Sentry never started]]
  # @lat: [[boot-step-error-reporting#Why BootStep rescues Exception and swallows reporting errors]]
  def self.report(name, exception)
    SwayLogging.log_exception("boot_step.failed", exception: exception, step: name)
    Sentry.capture_exception(exception, extra: {boot_step: name})
  rescue => reporting_error
    warn("BootStep could not report #{name} failing: #{reporting_error.class}: #{reporting_error.message}")
  end
end
