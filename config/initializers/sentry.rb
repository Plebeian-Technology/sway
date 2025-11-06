# frozen_string_literal: true

if Rails.env.production?
  Rails.logger.info("Sentry.init")

  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    # config.breadcrumbs_logger = [:active_support_logger, :http_logger]
    config.breadcrumbs_logger = [:active_support_logger]

    # https://docs.sentry.io/platforms/ruby/#configure
    # Add data like request headers and IP for users, if applicable;
    # see https://docs.sentry.io/platforms/ruby/data-management/data-collected/ for more info
    config.send_default_pii = false

    # Set traces_sample_rate to 1.0 to capture 100%
    # of transactions for tracing.
    # We recommend adjusting this value in production.
    config.traces_sample_rate = 1.0
    # or
    config.traces_sampler = lambda { |_context| true }
    # Set profiles_sample_rate to profile 100%
    # of sampled transactions.
    # We recommend adjusting this value in production.
    config.profiles_sample_rate = 1.0
  end
else
  Rails.logger.info("SKIP Sentry.init. Environment is NOT production.")
end
