# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  # @lat: [[twilio-error-phone-redaction#Why VotingReminderJob's inner rescue logs only structured fields and the error class]]
  class TwilioVerificationError < StandardError; end

  class VerifyServiceNotConfiguredError < Twilio::REST::TwilioError; end

  included do
    def send_phone_verification(session, phone_)
      # @lat: [[twilio-error-phone-redaction#Why the session guard checks for nil, not blank?]]
      return false if session.nil? || phone_.blank?

      phone = phone_.normalize_phone

      if Sway::Settings.dev_login.skip_phone_verification
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
        SwayLogging.info(
          "authentication.phone_verification_sent",
          phone_last4: phone.last(4)
        )

        true
      rescue Twilio::REST::RestError => e
        # @lat: [[twilio-error-phone-redaction#Why VotingReminderJob's inner rescue logs only structured fields and the error class]]
        SwayLogging.warn(
          "authentication.phone_verification_failed",
          phone_last4: phone.last(4),
          twilio_code: e.code
        )
        if Rails.env.production?
          Sentry.capture_exception(
            TwilioVerificationError.new("Twilio verification send failed (code=#{e.code}, status=#{e.status_code})")
          )
        end
        false
      rescue VerifyServiceNotConfiguredError
        false
      rescue Twilio::REST::TwilioError => e
        # @lat: [[twilio-error-phone-redaction#Why a Twilio network failure is answered, not raised]]
        SwayLogging.warn(
          "authentication.phone_verification_failed",
          phone_last4: phone.last(4),
          error_class: e.class.name
        )
        if Rails.env.production?
          Sentry.capture_exception(
            TwilioVerificationError.new("Twilio verification send failed (#{e.class.name})")
          )
        end
        false
      end
    end

    # @lat: [[twilio-error-phone-redaction#Why send_email_verification doesn't touch the session]]
    def send_email_verification(email)
      return false if email.blank?

      return true if Sway::Settings.dev_login.skip_phone_verification

      begin
        verification =
          twilio_client
            .verify
            .v2
            .services(service_sid)
            .verifications
            .create(to: email, channel: "email")

        SwayLogging.info("authentication.email_verification_sent") if verification.present?

        verification.present?
      rescue Twilio::REST::RestError => e
        # @lat: [[twilio-error-phone-redaction#Why VotingReminderJob's inner rescue logs only structured fields and the error class]]
        SwayLogging.warn(
          "authentication.email_verification_failed",
          twilio_code: e.code
        )
        if Rails.env.production?
          Sentry.capture_exception(
            TwilioVerificationError.new("Twilio email verification send failed (code=#{e.code}, status=#{e.status_code})")
          )
        end
        false
      end
    end

    # @lat: [[twilio-error-phone-redaction#Why verification_approved? catches nothing]]
    def verification_approved?(to:, code:)
      twilio_client
        .verify
        .v2
        .services(service_sid)
        .verification_checks
        .create(to: to, code: code)
        &.status == "approved"
    end

    private

    def twilio_client
      @twilio_client ||= Sway::TwilioClient.build
    end

    # @lat: [[env-secret-blank-value-handling#The two failure modes are not equally noisy]]
    def service_sid
      sid = EnvSecret.read("TWILIO_VERIFY_SERVICE_SID")
      return sid if sid

      # @lat: [[twilio-error-phone-redaction#Why a missing Verify service id is answered like an outage]]
      error = VerifyServiceNotConfiguredError.new("TWILIO_VERIFY_SERVICE_SID is not set")
      Sentry.capture_exception(error)
      raise error
    end
  end
end
