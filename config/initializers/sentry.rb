# frozen_string_literal: true

# @lat: [[local-error-reporting-design#Why CSP and Sentry initializers require SwayLocalErrorDsn directly]]
require_relative "../../lib/sway_local_error_dsn"
require_relative "../../lib/sway_local_error_reporting"

if Rails.env.production?
  Rails.logger.info("Sentry.init")

  Sentry.init do |config|
    # @lat: [[pre-autoload-credential-trimming#Sentry (config/initializers/sentry.rb)]]
    config.dsn = ENV["SENTRY_DSN"].to_s.strip.presence
    config.breadcrumbs_logger = [:active_support_logger]

    config.send_default_pii = false
    config.include_local_variables = false
    config.data_collection.user_info = false
    config.data_collection.http_bodies = []

    config.before_send = ->(event, hint) { SwayErrorScrubber.call(event, hint) }

    # @lat: [[sentry-error-reporting-lanes#Why the trace/profile sample rate is 10%, not a traces_sampler]]
    config.traces_sample_rate = 0.1
    config.profiles_sample_rate = 0.1

    # @lat: [[sentry-error-reporting-lanes#How errors reach Sentry in production]]
    config.rails.active_job_report_on_retry_error = false

    config.rails.structured_logging.enabled = false
  end
else
  # @lat: [[local-error-reporting-design#Why SwayLocalErrorDsn refuses rather than warns]]
  dsn = ENV["RUSTRAK_DSN"].to_s.strip.presence

  if dsn.nil?
    Rails.logger.info("SKIP Sentry.init. No RUSTRAK_DSN set.")
  elsif !SwayLocalErrorDsn.local?(dsn)
    Rails.logger.warn(
      "SKIP Sentry.init. RUSTRAK_DSN does not point at this machine, so error " \
      "reporting is OFF. Accepted hosts: #{SwayLocalErrorDsn::LOCAL_HOSTS.join(", ")}."
    )
  else
    Sentry.init { |config| SwayLocalErrorReporting.apply(config, dsn:) }

    Rails.logger.info("Sentry.init against the local error collector.")
  end
end
