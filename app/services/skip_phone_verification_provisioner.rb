# typed: true

# frozen_string_literal: true

class SkipPhoneVerificationProvisioner
  class << self
    def call(phone:)
      user =
        User.find_or_create_by(
          phone:,
          email: "#{phone}@sway.vote",
          full_name: ENV.fetch("DEFAULT_USER_FULL_NAME").tr("+", " "),
        )

      user.update!(
        phone:,
        is_admin: true,
        is_email_verified: true,
        is_phone_verified: true,
        is_registered_to_vote: true,
        is_registration_complete: true,
        registration_status: "completed",
      )

      address =
        Address.find_or_create_by(
          city: ENV.fetch("DEFAULT_CITY"),
          postal_code: ENV.fetch("DEFAULT_REGION_CODE"),
          region_code: ENV.fetch("DEFAULT_POSTAL_CODE"),
          street: ENV.fetch("DEFAULT_STREET").tr("+", " "),
          latitude: ENV.fetch("DEFAULT_LATITUDE").to_f,
          longitude: ENV.fetch("DEFAULT_LONGITUDE").to_f,
        )

      UserAddress.find_or_create_by(user:, address:)
      user
    end
  end
end
