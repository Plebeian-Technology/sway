# frozen_string_literal: true

require "anyway_config"
require_relative "settings/base"
require_relative "settings/upstream"
require_relative "settings/rate_limits"
require_relative "settings/legislation"
require_relative "settings/llm"
require_relative "settings/dev_login"
require_relative "settings/mobile"
require_relative "settings/ops"
require_relative "settings/webauthn"

module Sway
  # @lat: [[settings-value-resolution#Where a value comes from, in order]]
  module Settings
    class MissingValues < StandardError; end

    GROUPS = {
      upstream: Upstream,
      rate_limits: RateLimits,
      legislation: Legislation,
      llm: Llm,
      dev_login: DevLogin,
      mobile: Mobile,
      ops: Ops,
      webauthn: Webauthn
    }.freeze

    class << self
      # @lat: [[settings-build-suppress-validations#Why the kill-switch spec sets Anyway::Settings.suppress_required_validations directly, not just through with_env]]
      def build!
        Anyway::Settings.suppress_required_validations = ENV.key?("SECRET_KEY_BASE_DUMMY")

        built = {}
        failures = []

        GROUPS.each do |name, klass|
          built[name] = klass.new
        rescue Anyway::Config::ValidationError, ArgumentError => e
          failures << "  #{klass.config_name}: #{e.message}"
        end

        raise MissingValues, missing_message(failures) if failures.any?

        @instances = built
        self
      end

      def reset!
        @instances = {}
        self
      end

      def upstream
        cached = instances[:upstream]
        return cached if cached.is_a?(Upstream)

        instances[:upstream] = Upstream.new
      end

      def rate_limits
        cached = instances[:rate_limits]
        return cached if cached.is_a?(RateLimits)

        instances[:rate_limits] = RateLimits.new
      end

      # @lat: [[legislation-settings-group-design#Why every attribute defaults to nil]]
      def legislation
        cached = instances[:legislation]
        return cached if cached.is_a?(Legislation)

        instances[:legislation] = Legislation.new
      end

      def llm
        cached = instances[:llm]
        return cached if cached.is_a?(Llm)

        instances[:llm] = Llm.new
      end

      def dev_login
        cached = instances[:dev_login]
        return cached if cached.is_a?(DevLogin)

        instances[:dev_login] = DevLogin.new
      end

      def mobile
        cached = instances[:mobile]
        return cached if cached.is_a?(Mobile)

        instances[:mobile] = Mobile.new
      end

      def ops
        cached = instances[:ops]
        return cached if cached.is_a?(Ops)

        instances[:ops] = Ops.new
      end

      def webauthn
        cached = instances[:webauthn]
        return cached if cached.is_a?(Webauthn)

        instances[:webauthn] = Webauthn.new
      end

      def install(name, instance)
        instances[name] = instance
      end

      private

      def instances
        @instances ||= {}
      end

      def missing_message(failures)
        <<~MESSAGE
          Sway does not know some of its settings:

          #{failures.join("\n")}

          Each line above is either missing or holds text its declared type
          cannot read. Set it as an environment variable, or leave it unset
          so the class's own default applies.
        MESSAGE
      end
    end
  end
end
