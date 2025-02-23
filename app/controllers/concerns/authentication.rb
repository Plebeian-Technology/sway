# frozen_string_literal: true
# typed: true

module Authentication
  extend ActiveSupport::Concern
  extend T::Sig

  included do
    sig { params(phone: String).void }
    def authenticate(phone)
      # 1 - We try to find a User by phone. If present and has confirmed, check passkey
      user = find_by_phone(phone)

      # if user.present?
      #   if verified? && passkey?
      #     # sessions_controller.create
      #   elsif passkey?
      #     # somehow has a passkey and has not verified phone
      #     # phone_verification_controller.create
      #   else
      #     # has verified phone, but no passkey
      #     # actually this shouldn't happen, because
      #     # there exists a race condition where a phone is verified
      #     # and an attacker creates a passkey on another device
      #   end
      # else
      #   # user does not exist, phone_verification_controller.create
      # end

      # The above can be simplified to:
      if user.present? && verified? && passkey?
        # sessions_controller.create
      else
        # phone_verification_controller.create
      end
    end

    def send_phone_verification(session, phone_)
      return false unless session.present? && phone_.present?

      phone = phone_.remove_non_digits

      begin
        verification = twilio_client.verify.v2.services(service_sid).verifications.create(
          to: "+1#{phone}",
          channel: "sms"
        )

        session[:phone] = phone if verification.present?

        true
      rescue Twilio::REST::RestError => e
        Rails.logger.error e.full_message
        Sentry.capture_exception(e)
        false
      end
    end

    def send_email_verification(session, email)
      return false unless session.present? && email.present?

      begin
        verification = twilio_client.verify.v2.services(service_sid).verifications.create({
          to: email,
          channel: "email"
        })

        session[:email] = email if verification.present?

        true
      rescue Twilio::REST::RestError => e
        Rails.logger.error e.full_message
        Sentry.capture_exception(e)
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
