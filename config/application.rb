require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SwayRails
    class Application < Rails::Application
        # Initialize configuration defaults for originally generated Rails version.
        config.load_defaults 7.1

        # Please, add to the `ignore` list any other `lib` subdirectories that do
        # not contain `.rb` files, or that should not be reloaded or eager loaded.
        # Common ones are `templates`, `generators`, or `middleware`, for example.
        config.autoload_lib(ignore: %w[assets tasks])

        # Configuration for the application, engines, and railties goes here.
        #
        # These settings can be overridden in specific environments using the files
        # in config/environments, which are processed later.
        #
        # config.time_zone = "Central Time (US & Canada)"
        # config.eager_load_paths << Rails.root.join("extras")
        config.time_zone = "UTC"

        config.force_ssl = false

        # Addresses deprecation warning:
        # DEPRECATION WARNING: `to_time` will always preserve the full timezone rather than offset of the receiver in Rails 8.1. To opt in to the new behavior, set `config.active_support.to_time_preserves_timezone = :zone`.
        # Just do what Thoughtbot did - https://github.com/thoughtbot/administrate/pull/2753/files
        config.active_support.to_time_preserves_timezone = :zone
    end
end
