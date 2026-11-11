# frozen_string_literal: true

module Sway
  # @lat: [[twilio-error-phone-redaction#Why Sway::TwilioClient centralizes the Twilio::REST::Client build]]
  class TwilioClient
    def self.build
      Twilio::REST::Client.new(
        EnvSecret.read("TWILIO_ACCOUNT_SID"),
        EnvSecret.read("TWILIO_AUTH_TOKEN")
      )
    end

    # Returns the sending number as "(XXX) XXX-XXXX", or nil when it is unset
    # or is not a ten-digit North American number.
    # @lat: [[sms-notification-service-design#Where the displayed Sway number comes from]]
    def self.display_from_phone
      digits = EnvSecret.read("TWILIO_FROM_PHONE").to_s.delete("^0-9")
      digits = digits.delete_prefix("1") if digits.length == 11
      return nil unless digits.length == 10

      "(#{digits[0, 3]}) #{digits[3, 3]}-#{digits[6, 4]}"
    end
  end
end
