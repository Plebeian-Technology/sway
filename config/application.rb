require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

# @lat: [[lat#Sway]]
module SwayRails
  class Application < Rails::Application
    # @lat: [[settings-initializer-load-order#Why the settings initializer runs after :load_environment_config]]
    require_relative "../lib/sway/settings"
    require_relative "../lib/sway_logging"
    require_relative "../lib/boot_step"
    require_relative "../app/lib/env_secret"

    # @lat: [[settings-initializer-load-order#Why the ordering is load-bearing]]
    # @lat: [[boot-failure-reporting#A missing setting is reported before it stops the boot]]
    initializer "sway.settings", after: :load_environment_config do |_app|
      BootStep.run("sway.settings") { Sway::Settings.build! }
    end

    config.load_defaults 8.1

    # @lat: [[settings-and-secrets#Active Record encryption keys]]
    # @lat: [[active-record-encryption-keys]]
    {
      primary_key: EnvSecret.read("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"),
      deterministic_key: EnvSecret.read("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"),
      key_derivation_salt: EnvSecret.read("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT")
    }.each do |name, value|
      config.active_record.encryption[name] = value if value
    end

    # @lat: [[personal-detail-encryption#Reading rows the backfill has not reached]]
    config.active_record.encryption.support_unencrypted_data = true
    config.active_record.encryption.extend_queries = true

    # @lat: [[rubocop-cops-autoload-exclusion#Why cops is excluded from autoload_lib]]
    config.autoload_lib(ignore: %w[assets tasks cops])

    config.time_zone = "UTC"

    # @lat: [[content-security-policy#Why CORS is not configured]]
    config.force_ssl = false

    require_relative "../app/middleware/cloudflare_connecting_ip_middleware"
    # @lat: [[cloudflare-trusted-proxies#Why CloudflareConnectingIpMiddleware normalizes X-Forwarded-For before RemoteIp]]
    config.middleware.insert_before ActionDispatch::RemoteIp, CloudflareConnectingIpMiddleware

    require_relative "../app/middleware/bad_request_middleware"
    # @lat: [[bad-request-responses#Why it sits above the method-override check]]
    config.middleware.insert_before Rack::MethodOverride, BadRequestMiddleware

    require_relative "../app/middleware/reporting_endpoints_middleware"
    config.middleware.insert_after ActionDispatch::Static, ReportingEndpointsMiddleware

    require_relative "../app/middleware/service_worker_allowed_middleware"
    # @lat: [[static-asset-cache-headers#Why ServiceWorkerAllowedMiddleware sits before ActionDispatch::Static]]
    config.middleware.insert_before ActionDispatch::Static, ServiceWorkerAllowedMiddleware
  end
end
