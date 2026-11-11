# frozen_string_literal: true

class SkipPhoneVerificationProvisioner
  # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
  class << self
    def call(phone:)
      # @lat: [[identity-and-access#The phone-verification bypass is inert outside development]]
      unless Rails.env.local?
        raise "SkipPhoneVerificationProvisioner is a dev/test-only convenience and must never run in production"
      end

      # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address#The phone-verification shortcut does not grant admin access]]
      # @lat: [[personal-detail-encryption#An encrypted column cannot be a lookup key]]
      user = User.find_or_initialize_by(phone:)
      new_record = user.new_record?

      User.transaction do
        if new_record
          full_name = Sway::Settings.dev_login.dev_account_full_name #: String
          user.assign_attributes(email: "#{phone}@sway.vote", full_name: full_name.tr("+", " "))
          user.save!
          user.update!(
            is_email_verified: true,
            is_phone_verified: true,
            is_registered_to_vote: true
          )

          sway_locale = sample_address_locale
          address = DevelopmentAccountAddressService.resolve(sway_locale:)
          # @lat: [[identity-and-access#A user holds one address]]
          UserAddress.create!(user:, address:)
        elsif user.registered?
          user.complete! if user.registration_status != "completed" || !user.is_registration_complete
        else
          user.update!(is_email_verified: true, is_phone_verified: true)
        end
      end
      user
    end

    private

    def sample_address_locale
      name = Sway::Settings.dev_login.dev_account_sway_locale #: String
      found = SwayLocale.resolve_by_computed_name(name)
      if found.nil?
        raise "DEV_ACCOUNT_SWAY_LOCALE names #{name}, which is not a sway locale in this database"
      end

      found #: SwayLocale
    end
  end
end
