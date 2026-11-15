# frozen_string_literal: true

module Api
  module V1
    class PhoneVerificationsController < BaseController
      include Authentication
      include OnboardingSafetyNet

      # @lat: [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day]]
      rate_limit to: 30, within: 1.hour,
        name: "request_code_ip",
        by: -> { request.remote_ip },
        only: :request_code,
        if: -> { RateLimitConfig.enabled?(:phone_verify) },
        with: -> {
          # @type self: Api::V1::PhoneVerificationsController
          response.set_header("Retry-After", 1.hour.to_i.to_s)
          render_error(code: "rate_limited", message: "Too many SMS requests", status: :too_many_requests)
        },
        store: ApplicationController::RATE_LIMIT_STORE
      rate_limit to: 10, within: 1.minute,
        name: "verify_ip",
        by: -> { request.remote_ip },
        only: :verify,
        if: -> { RateLimitConfig.enabled?(:phone_verify) },
        with: -> {
          # @type self: Api::V1::PhoneVerificationsController
          response.set_header("Retry-After", 1.minute.to_i.to_s)
          render_error(code: "rate_limited", message: "Too many verification attempts", status: :too_many_requests)
        },
        store: ApplicationController::RATE_LIMIT_STORE
      rate_limit to: 5, within: 10.minutes,
        name: "verify_phone",
        # @lat: [[phone-cache-hashing]]
        by: -> { PhoneCacheKey.digest(params[:phone]) },
        only: :verify,
        if: -> { RateLimitConfig.enabled?(:phone_verify) },
        with: -> {
          # @type self: Api::V1::PhoneVerificationsController
          response.set_header("Retry-After", 10.minutes.to_i.to_s)
          render_error(code: "rate_limited", message: "Too many attempts for this number", status: :too_many_requests)
        },
        store: ApplicationController::RATE_LIMIT_STORE

      def public_endpoint?
        true
      end

      def request_code
        phone = params.require(:phone).to_s.normalize_phone
        unless phone.possible_us_phone?
          return render_error(code: "invalid_phone", message: "Enter a valid US phone number.", status: :unprocessable_content)
        end

        if Sway::Settings.dev_login.skip_phone_verification
          # @lat: [[identity-and-access#The phone-verification bypass is inert outside development]]
          SwayLogging.info(
            "api_v1.phone_verification.create_skipped",
            phone_last4: phone.last(4)
          )
          return head :no_content
        end

        wait = phone_verification_send_wait(phone)
        return render_rate_limited(retry_after: wait) if wait

        sent = false
        begin
          twilio_client.verify.v2.services(service_sid).verifications.create(
            to: "+1#{phone}",
            channel: "sms"
          )
          sent = true
          SwayLogging.info(
            "api_v1.phone_verification.create_requested",
            phone_last4: phone.last(4)
          )
          head :no_content
        rescue Twilio::REST::RestError => e
          # @lat: [[twilio-error-phone-redaction#Why PhoneVerificationController.update reads e.full_message only to branch]]
          SwayLogging.warn(
            "api_v1.phone_verification.create_failed",
            phone_last4: phone.last(4),
            twilio_code: e.code
          )
          if e.code == Authentication::TWILIO_MAX_SEND_ATTEMPTS_CODE
            return render_rate_limited(retry_after: Authentication::TWILIO_MAX_SEND_ATTEMPTS_WAIT.to_i)
          end

          render_error(code: "verification_unavailable", message: "Could not send verification code", status: :service_unavailable)
        rescue Twilio::REST::TwilioError => e
          # @lat: [[twilio-error-phone-redaction#Why a Twilio network failure is answered, not raised]]
          SwayLogging.warn(
            "api_v1.phone_verification.create_failed",
            phone_last4: phone.last(4),
            error_class: e.class.name
          )
          render_error(code: "verification_unavailable", message: "Could not send verification code", status: :service_unavailable)
        ensure
          release_phone_verification_send(phone) unless sent
        end
      end

      def verify
        phone = params.require(:phone).to_s.normalize_phone
        code = params.fetch(:code).to_s.strip

        unless phone.possible_us_phone?
          return render_error(code: "invalid_phone", message: "Enter a valid US phone number.", status: :unprocessable_content)
        end

        if code.blank?
          return render_error(code: "invalid_code", message: "Verification code is required", status: :unprocessable_content)
        end

        approved = Sway::Settings.dev_login.skip_phone_verification || begin
          verification_approved?(to: "+1#{phone}", code: code)
        rescue Twilio::REST::RestError => e
          # @lat: [[twilio-error-phone-redaction#Why PhoneVerificationController.update reads e.full_message only to branch]]
          SwayLogging.warn(
            "api_v1.phone_verification.verify_failed",
            phone_last4: phone.last(4),
            twilio_code: e.code
          )
          false
        rescue Twilio::REST::TwilioError => e
          # @lat: [[twilio-error-phone-redaction#Why a Twilio network failure is answered, not raised]]
          SwayLogging.warn(
            "api_v1.phone_verification.verify_failed",
            phone_last4: phone.last(4),
            error_class: e.class.name
          )
          return render_error(code: "verification_unavailable", message: "Could not check verification code", status: :service_unavailable)
        end

        unless approved
          return render_error(
            code: "invalid_code",
            message: "Verification code invalid or expired",
            status: :unauthorized
          )
        end

        token = SmsVerificationToken.issue!(phone)
        render json: {
          sms_verified_token: token,
          expires_at: (Time.current + SmsVerificationToken::TTL).iso8601
        }
      end
    end
  end
end
