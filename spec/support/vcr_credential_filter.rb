# frozen_string_literal: true

require "support/env_credential_scanner"

# @lat: [[vcr-credential-filter-design#Why a text-scan test, not a behavior test, catches a dead filter]]
module VcrCredentialFilter
  # @lat: [[vcr-credential-filter-design#Why the spec runs VCR's real before_record hook chain instead of a stand-in]]
  MINIMUM_REDACTABLE_CHARS = 12

  class << self
    # @return [Array<String>] the provisioned credential names.
    def credential_names
      @credential_names ||= EnvCredentialScanner.new.credential_names
    end

    # @param config [VCR::Configuration]
    # @return [void]
    def apply!(config)
      credential_names.each do |name|
        # The block runs late — VCR calls it for each interaction while
        # recording or playing back, not when it is registered — so a variable a
        # spec sets is seen, and a variable set only during the recording run
        # (VCR=record) is picked up there without needing to exist here.
        config.filter_sensitive_data("<#{name}>") { redactable_value(name) }
      end
    end

    # @param name [String]
    # @return [String, nil] the value to blank out, or nil when there is nothing safe to blank out.
    # @lat: [[vcr-credential-filter-design#Why redactable_value returns nil, not an empty string, for nothing to blank out]]
    def redactable_value(name)
      value = ENV[name].to_s.strip
      return nil if value.length < MINIMUM_REDACTABLE_CHARS

      value
    end
  end
end
