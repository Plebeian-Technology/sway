# frozen_string_literal: true

require_relative "sway_error_scrubber"
require_relative "sway_gzip_only_transport"

# @lat: [[browser-error-reporting#Browser error reporting#Development reports stay on this machine]]
module SwayLocalErrorReporting
  module_function

  def apply(config, dsn:)
    config.dsn = dsn
    config.breadcrumbs_logger = [:active_support_logger]

    # @lat: [[local-error-reporting-design#Why config.environment is set explicitly]]
    config.environment = Rails.env.to_s

    # @lat: [[local-error-reporting-design#Why send_default_pii and include_local_variables are set explicitly]]
    config.send_default_pii = false
    config.include_local_variables = false

    config.traces_sample_rate = 0.0
    config.profiles_sample_rate = 0.0

    config.before_send = ->(event, hint) { SwayErrorScrubber.call(event, hint) }

    # @lat: [[local-error-reporting-design#Why SwayGzipOnlyTransport always compresses]]
    config.transport.transport_class = SwayGzipOnlyTransport

    config.rails.active_job_report_on_retry_error = false

    config
  end
end
