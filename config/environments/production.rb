require "active_support/core_ext/integer/time"

# @lat: [[settings-initializer-load-order#Why the settings initializer runs after :load_environment_config]]
require_relative "../../lib/sway_deploy_config"

Rails.application.configure do
  app_host = ENV.fetch("APP_HOST", "app.sway.vote")
  app_protocol = ENV.fetch("APP_PROTOCOL", "https")
  app_port = ENV["APP_PORT"].presence
  app_port = nil if %w[80 443].include?(app_port)
  app_base_url =
    ENV.fetch(
      "APP_BASE_URL",
      ["#{app_protocol}://#{app_host}", app_port].compact.join(":")
    )
  default_url_options = {host: app_host, protocol: app_protocol}
  default_url_options[:port] = app_port if app_port.present?
  # @lat: [[production-allowed-hosts-no-fallback#Why there is no fallback for RAILS_ALLOWED_HOSTS]]
  allowed_hosts =
    SwayDeployConfig
      .fetch("RAILS_ALLOWED_HOSTS")
      .split(",")
      .map(&:strip)
      .compact_blank

  config.enable_reloading = false

  config.eager_load = true

  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  config.require_master_key = true

  config.assets.compile = false

  config.active_storage.service = :google
  config.active_storage.variant_processor = :disabled

  # @lat: [[cloudflare-trusted-proxies#Why production emits HSTS without redirecting or preloading]]
  # @lat: [[cloudflare-trusted-proxies#Why spec/requests/force_ssl_spec.rb checks config files and deleted methods, not live HTTPS behavior]]
  if ENV["DISABLE_FORCE_SSL"] == "true"
    config.force_ssl = false
  else
    config.force_ssl = true
    config.ssl_options = {
      redirect: false,
      hsts: {
        expires: 1.year,
        subdomains: true,
        preload: false
      },
      secure_cookies: true
    }
  end

  config.log_tags = [:request_id]

  config.log_level =
    ENV.fetch("RAILS_LOG_LEVEL", Rails.env.production? ? "info" : "debug")

  config.logger = Logger.new($stdout)

  # @lat: [[auxiliary-databases#The Solid Cache database replaces two different broken caches]]
  # @lat: [[identity-and-access#The rate limit store swaps in after boot]]
  config.cache_store = :solid_cache_store

  # @lat: [[static-asset-cache-headers#Why a year is safe rather than reckless]]
  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=31536000, immutable"
  }

  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = {database: {writing: :queue}}
  config.solid_queue.logger = ActiveSupport::Logger.new($stdout, level: Logger::INFO)

  config.action_mailer.perform_caching = false

  # @lat: [[outbound-email#Outbound email#Delivery goes over HTTPS, not SMTP]]
  config.action_mailer.delivery_method = :resend
  config.action_mailer.default_url_options = default_url_options
  config.action_mailer.asset_host = app_base_url
  # @lat: [[routes-default-url-options-sync#Development: why config.x.default_url_options is set separately]]
  config.x.default_url_options = default_url_options
  Rails.application.routes.default_url_options = default_url_options

  # @lat: [[catch-all-enabled-production-only#Why the app's own machinery is excluded from the catch-all]]
  config.x.catch_all_enabled = true

  config.i18n.fallbacks = true
  config.active_support.report_deprecations = false
  config.active_record.dump_schema_after_migration = false

  allowed_hosts.each { |host| config.hosts << host }

  config.host_authorization = {exclude: ->(request) { request.path == "/up" }}
end
