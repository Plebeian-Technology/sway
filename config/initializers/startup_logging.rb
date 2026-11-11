# frozen_string_literal: true

unless Rails.env.test?
  Rails.application.config.after_initialize do
    primary_database_config =
      ActiveRecord::Base.configurations.configs_for(
        env_name: Rails.env,
        name: "primary"
      )
    queue_database_config =
      ActiveRecord::Base.configurations.configs_for(
        env_name: Rails.env,
        name: "queue"
      )
    # @lat: [[auxiliary-databases#Why cable messages don't live on the primary database]]
    cable_database_config =
      ActiveRecord::Base.configurations.configs_for(
        env_name: Rails.env,
        name: "cable"
      )
    # @lat: [[auxiliary-databases#The Solid Cache database replaces two different broken caches]]
    cache_database_config =
      ActiveRecord::Base.configurations.configs_for(
        env_name: Rails.env,
        name: "cache"
      )

    SwayLogging.info(
      "app_boot",
      rails_env: Rails.env,
      # @lat: [[routes-default-url-options-sync#Development: why config.x.default_url_options is set separately]]
      app_base_url:
        (
          Rails.application.config.x.default_url_options.presence ||
            Rails.application.routes.default_url_options
        )&.then do |options|
          if options.present?
            [
              "#{options[:protocol]}://#{options[:host]}",
              options[:port].presence
            ].compact.join(":")
          end
        end,
      active_storage_service: Rails.application.config.active_storage.service,
      queue_adapter: Rails.application.config.active_job.queue_adapter,
      primary_database:
        primary_database_config&.configuration_hash&.dig(:database),
      queue_database: queue_database_config&.configuration_hash&.dig(:database),
      cable_database: cable_database_config&.configuration_hash&.dig(:database),
      cache_database: cache_database_config&.configuration_hash&.dig(:database)
    )
  end
end
