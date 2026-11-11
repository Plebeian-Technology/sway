# frozen_string_literal: true

# @lat: [[error-reporting-in-tests#What a test run reports, and what it leaves alone]]
module ReportApplicationErrors
  # Captured once, so a spec that replaces the Sentry constant with a double
  # cannot make this harness answer to it and fail the example it was helping.
  SENTRY = (defined?(::Sentry) ? ::Sentry : nil)

  # Measured: MultipleExpectationsNotMetError (aggregate_failures) subclasses
  # ExpectationNotMetError, so one entry covers both.
  TEST_FAILURES = [
    RSpec::Expectations::ExpectationNotMetError,
    RSpec::Mocks::MockExpectationError,
    RSpec::Core::Pending::PendingExampleFixedError
  ].freeze

  module_function

  def test_failure?(exception)
    TEST_FAILURES.any? { |klass| exception.is_a?(klass) }
  end

  # @lat: [[application-errors-sentry-relay-design#Why the recursion is duck-typed on respond_to?(:all_exceptions)]]
  def application_errors(exception)
    return [] if exception.nil?

    if exception.respond_to?(:all_exceptions)
      # public_send, because no type covers both bundle shapes and steep does
      # not narrow on respond_to?.
      inner = Array(exception.public_send(:all_exceptions)) - [exception]
      return inner.flat_map { |one| application_errors(one) }
    end

    test_failure?(exception) ? [] : [exception]
  end

  # Holding the module is not enough: sentry-ruby re-resolves the Sentry constant
  # internally, so a call still lands on a spec's double (measured 2026-08-12 —
  # capture_exception asked a double `exception_captured?`). Stand down instead.
  def reporting?
    sentry = SENTRY
    return false unless sentry

    live_sentry_constant.equal?(sentry) && sentry.initialized?
  end

  def live_sentry_constant
    Object.const_get(:Sentry)
  rescue NameError
    nil
  end

  # On every event, not just escaped ones, so a deliberate error-path test can be
  # told from a surprise without reading the stack.
  def tags_for(example)
    {"rspec.example" => example.location.to_s, "rspec.description" => example.full_description.to_s}
  end
end

RSpec.configure do |config|
  # around: RSpec runs the after hook below inside it, so both are tagged.
  config.around do |example|
    sentry = ReportApplicationErrors::SENTRY

    if sentry && ReportApplicationErrors.reporting?
      sentry.with_scope do |scope|
        scope.set_tags(ReportApplicationErrors.tags_for(example))
        example.run
      end
    else
      example.run
    end
  end

  # append_after: runs last, so an earlier after hook's exception is already set.
  config.append_after do |example|
    sentry = ReportApplicationErrors::SENTRY
    next unless sentry && ReportApplicationErrors.reporting?

    ReportApplicationErrors.application_errors(example.exception).each do |error|
      sentry.capture_exception(error)
    end
  end
end
