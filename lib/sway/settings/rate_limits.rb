# frozen_string_literal: true

module Sway
  module Settings
    # @lat: [[rate-limit-kill-switches#Why the preferences scope is rate-limited by IP]]
    class RateLimits < Base
      config_name "rate_limits"
      env_prefix "RATE_LIMIT"

      attr_config sign_in_enabled: true
      coerce_types sign_in_enabled: :boolean
      required :sign_in_enabled

      attr_config sign_up_enabled: true
      coerce_types sign_up_enabled: :boolean
      required :sign_up_enabled

      attr_config phone_verify_enabled: true
      coerce_types phone_verify_enabled: :boolean
      required :phone_verify_enabled

      attr_config email_verify_enabled: true
      coerce_types email_verify_enabled: :boolean
      required :email_verify_enabled

      attr_config legislator_email_enabled: true
      coerce_types legislator_email_enabled: :boolean
      required :legislator_email_enabled

      attr_config csp_report_enabled: true
      coerce_types csp_report_enabled: :boolean
      required :csp_report_enabled

      attr_config org_invite_enabled: true
      coerce_types org_invite_enabled: :boolean
      required :org_invite_enabled

      attr_config device_push_token_enabled: true
      coerce_types device_push_token_enabled: :boolean
      required :device_push_token_enabled

      attr_config bootstrap_enabled: true
      coerce_types bootstrap_enabled: :boolean
      required :bootstrap_enabled

      attr_config preferences_enabled: true
      coerce_types preferences_enabled: :boolean
      required :preferences_enabled

      attr_config bill_summary_report_enabled: true
      coerce_types bill_summary_report_enabled: :boolean
      required :bill_summary_report_enabled

      RECOGNIZED_BOOLEAN_WORDS = %w[true yes y 1 t false no n 0 f].freeze
      private_constant :RECOGNIZED_BOOLEAN_WORDS

      # @lat: [[rate-limit-kill-switches#Why the typo guard reads the raw env value]]
      on_load do
        (self.class.config_attributes || []).each do |attribute|
          env_name = [self.class.env_prefix, attribute.to_s.upcase].reject(&:empty?).join("_")
          raw = ENV.fetch(env_name, nil)
          next if raw.nil?

          stripped = raw.strip.downcase
          next if stripped.empty? || RECOGNIZED_BOOLEAN_WORDS.include?(stripped)

          raise ArgumentError, "#{env_name}: not a yes-or-no value: #{stripped.inspect}"
        end
      end

      # @lat: [[settings-groups#Why the freeze runs after a group's own repair]]
      on_load { self.class.freeze_mutable_attributes!(self) }
    end
  end
end
