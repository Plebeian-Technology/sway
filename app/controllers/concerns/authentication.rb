# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  # @lat: [[twilio-error-phone-redaction#Why VotingReminderJob's inner rescue logs only structured fields and the error class]]
  class TwilioVerificationError < StandardError; end

  class VerifyServiceNotConfiguredError < Twilio::REST::TwilioError; end

  # @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day#A sixth send inside one verification is answered with a wait]]
  TWILIO_MAX_SEND_ATTEMPTS_CODE = 60203
  TWILIO_MAX_SEND_ATTEMPTS_WAIT = 10.minutes

  included do
    def send_phone_verification(session, phone_)
      # @lat: [[twilio-error-phone-redaction#Why the session guard checks for nil, not blank?]]
      return false if session.nil? || phone_.blank?

      phone = phone_.normalize_phone

      if Sway::Settings.dev_login.skip_phone_verification
        session[:phone] = phone
        return true
      end

      sent = false
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

        sent = true
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
        (e.code == TWILIO_MAX_SEND_ATTEMPTS_CODE) ? :send_attempts_exhausted : false
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
      ensure
        release_phone_verification_send(phone) unless sent
      end
    end

    # @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day#A sixth send inside one verification is answered with a wait]]
    def render_phone_verification_send(session, phone, **extra)
      sent = send_phone_verification(session, phone)
      return render_rate_limited(retry_after: TWILIO_MAX_SEND_ATTEMPTS_WAIT.to_i) if sent == :send_attempts_exhausted

      render json: {**extra, success: sent}, status: :ok
    end

    # @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day]]
    def phone_verification_send_wait(phone)
      return nil unless RateLimitConfig.enabled?(:phone_verify)

      now = Time.current
      wait = PhoneVerificationSendLimit.claim(
        phone: phone,
        store: ApplicationController::RATE_LIMIT_STORE,
        now: now
      )
      @phone_verification_send_claim = {phone: phone, sent_at: now.to_i} if wait.nil?
      wait
    rescue => e
      SwayLogging.log_exception("authentication.phone_send_limit_failed", exception: e, level: :warn)
      nil
    end

    # @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day#A send Twilio refuses gives its daily slot back]]
    def release_phone_verification_send(phone)
      claim = @phone_verification_send_claim
      return if claim.nil? || claim[:phone].to_s.normalize_phone != phone.to_s.normalize_phone

      @phone_verification_send_claim = nil
      PhoneVerificationSendLimit.release(
        phone: phone,
        store: ApplicationController::RATE_LIMIT_STORE,
        sent_at: claim[:sent_at]
      )
    rescue => e
      SwayLogging.log_exception("authentication.phone_send_release_failed", exception: e, level: :warn)
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
