# frozen_string_literal: true
# typed: true

module Authentication
  extend ActiveSupport::Concern
  extend T::Sig

  included do
    def send_phone_verification(session, phone_)
      return false unless session.present? && phone_.present?

      phone = phone_.remove_non_digits

      if ENV.fetch("SKIP_PHONE_VERIFICATION", nil).present?
        session[:phone] = phone
        return true
      end

      begin
        verification =
          twilio_client
            .verify
            .v2
            .services(service_sid)
            .verifications
            .create(to: "+1#{phone}", channel: "sms")

        session[:phone] = phone if verification.present?

        true
      rescue Twilio::REST::RestError => e
        Rails.logger.error(e.full_message)
        Sentry.capture_exception(e) if Rails.env.production?
        false
      end
    end

    def send_email_verification(session, email)
      return false unless session.present? && email.present?

      begin
        verification =
          twilio_client
            .verify
            .v2
            .services(service_sid)
            .verifications
            .create(to: email, channel: "email")

        session[:email] = email if verification.present?

        true
      rescue Twilio::REST::RestError => e
        Rails.logger.error e.full_message
        Sentry.capture_exception(e) if Rails.env.production?
        false
      end
    end

    private

    def twilio_client
      @twilio_client ||= Twilio::REST::Client.new(account_sid, auth_token)
    end

    def account_sid
      ENV["TWILIO_ACCOUNT_SID"]
    end

    def auth_token
      ENV["TWILIO_AUTH_TOKEN"]
    end

    def service_sid
      ENV["TWILIO_VERIFY_SERVICE_SID"]
    end

    # sig { params(phone: String).returns(T::Boolean) }
    # def authenticatable(phone)
    #   @user&.phone&.present? && verified?
    # end

    sig { returns(T::Boolean) }
    def verified?
      @user&.is_phone_verified
    end

    sig { returns(T::Boolean) }
    def passkey?
      @user&.passkeys&.size&.> 0
    end

    sig { params(phone: String).returns(T.nilable(User)) }
    def find_by_phone(phone)
      @find_by_phone ||= User.find_by(phone:)
    end
  end
end
