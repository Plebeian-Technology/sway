# @lat: [[test-release-sha-pin#Why the release SHA is pinned before Rails boots in test]]
ENV["SWAY_RELEASE_SHA"] ||= "0" * 40

require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false

  config.eager_load = ENV["CI"].present?

  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=#{1.hour.to_i}"
  }

  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store
  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false
  config.active_storage.service = :test

  config.action_mailer.perform_caching = false

  config.action_mailer.delivery_method = :test

  config.action_mailer.default_url_options = {host: "www.example.com"}

  config.active_support.deprecation = :raise
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []
  config.action_controller.raise_on_missing_callback_actions = true

  # @lat: [[migrate-from-empty-spec-design#Why the schema-file check compares mtimes, not contents]]
  config.active_record.dump_schema_after_migration = false

  # @lat: [[active-record-encryption-keys#Test environment keys]]
  config.active_record.encryption.primary_key = "test-primary-key-not-a-real-secret"
  config.active_record.encryption.deterministic_key = "test-deterministic-key-not-a-real-secret"
  config.active_record.encryption.key_derivation_salt = "test-key-derivation-salt-not-a-real-secret"
end
