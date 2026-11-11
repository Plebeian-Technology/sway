require "active_support/core_ext/integer/time"

# @lat: [[settings-initializer-load-order#Why the settings initializer runs after :load_environment_config]]
require_relative "../../lib/sway_deploy_config"

Rails.application.configure do
  docker_address =
    begin
      if ENV["IS_DOCKER"].present?
        "#{Resolv.getaddress("host.docker.internal")}/32"
      end
    rescue
      nil
    end

  tunnel_host = ENV["DEV_TUNNEL_HOST"].to_s.strip
  config.web_console.permissions =
    if tunnel_host.present? && tunnel_host != "localhost"
      []
    else
      [
        docker_address.presence,
        "127.0.0.1/8"
      ].compact
    end
  config.web_console.whiny_requests = false

  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  # @lat: [[auxiliary-databases#Why development's cache has to be a real store]]
  config.cache_store = :solid_cache_store

  if Rails.root.join("tmp", "caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true
    config.public_file_server.headers = {
      "Cache-Control" => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false
  end

  config.active_storage.service = :local
  config.active_storage.variant_processor = :disabled

  config.action_mailer.raise_delivery_errors = false

  config.action_mailer.perform_caching = false

  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {address: "127.0.0.1", port: 1025}
  config.action_mailer.default_url_options = {host: "localhost", port: 3000}
  # @lat: [[routes-default-url-options-sync#Development: why config.x.default_url_options is set separately]]
  config.x.default_url_options = {
    host: "localhost",
    port: 3333,
    protocol: "https"
  }
  config.action_mailer.asset_host = "https://localhost:3333"

  config.active_support.deprecation = :log
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true
  config.active_job.verbose_enqueue_logs = true
  config.assets.quiet = true
  config.action_view.annotate_rendered_view_with_filenames = true
  config.action_controller.raise_on_missing_callback_actions = true

  config.hosts = %w[
    web:3333
    localhost:3333
    127.0.0.1:3333
    web:3000
    localhost:3000
    127.0.0.1:3000
  ]

  # @lat: [[deploy-values-boot-check]]
  Array(SwayDeployConfig["SWAY_DEV_ALLOWED_HOSTS"]&.split(","))
    .map(&:strip)
    .compact_blank
    .each { |host| config.hosts << host }

  # @lat: [[production-allowed-hosts-no-fallback#Development allowed hosts and DEV_TUNNEL_HOST]]
  config.hosts << ENV["DEV_TUNNEL_HOST"] if ENV["DEV_TUNNEL_HOST"].present?

  config.log_level = "info"

  # @lat: [[sway-logging-design#Why development broadcasts logs to both stdout and development.log]]
  development_log = Logger.new(Rails.root.join("log", "development.log"))
  config.logger = ActiveSupport::BroadcastLogger.new(
    Logger.new($stdout),
    development_log
  )

  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = {database: {writing: :queue}}
  config.solid_queue.logger = ActiveSupport::BroadcastLogger.new(
    Logger.new($stdout),
    development_log
  )

  # @lat: [[active-record-encryption-keys#Development environment keys]]
  config.active_record.encryption.primary_key = "development-primary-key-not-a-real-secret"
  config.active_record.encryption.deterministic_key = "development-deterministic-key-not-a-real-secret"
  config.active_record.encryption.key_derivation_salt = "development-key-derivation-salt-not-a-real-secret"
end
