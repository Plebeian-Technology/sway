# frozen_string_literal: true

module Sway
  module Settings
    # @lat: [[settings-groups#Why some groups declare a blank env prefix]]
    class DevLogin < Base
      config_name "dev_login"
      env_prefix ""

      # @lat: [[settings-groups#Why the base class replaces the gem's casters]]
      attr_config skip_phone_verification: false
      coerce_types skip_phone_verification: :boolean
      required :skip_phone_verification

      # @lat: [[identity-and-access#The phone-verification bypass is inert outside development]]
      def skip_phone_verification
        super && Rails.env.local?
      end

      def skip_phone_verification?
        skip_phone_verification
      end

      # @lat: [[settings-group-declaration-notes#Why dev_account_full_name (and its siblings) have a real default]]
      attr_config dev_account_full_name: "Sway+Admin"
      coerce_types dev_account_full_name: :string

      # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
      attr_config dev_account_sway_locale: "baltimore-maryland-united_states"
      coerce_types dev_account_sway_locale: :string

      # @lat: [[settings-groups#Why the freeze runs after a group's own repair]]
      on_load { self.class.freeze_mutable_attributes!(self) }
    end
  end
end
