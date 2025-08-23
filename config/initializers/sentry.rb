# frozen_string_literal: true

if Rails.env.production?
  Rails.logger.info("Sentry.init")

  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    # config.breadcrumbs_logger = [:active_support_logger, :http_logger]
    config.breadcrumbs_logger = [:active_support_logger]

    config.enable_tracing = true

    # Set traces_sample_rate to 1.0 to capture 100%
    # of transactions for tracing.
    # We recommend adjusting this value in production.
    config.traces_sample_rate = 1.0
    # or
    config.traces_sampler = lambda do |context|
      true
    end
    # Set profiles_sample_rate to profile 100%
    # of sampled transactions.
    # We recommend adjusting this value in production.
    config.profiles_sample_rate = 1.0
  end
else
  Rails.logger.info("SKIP Sentry.init. Environment is NOT production.")
end
