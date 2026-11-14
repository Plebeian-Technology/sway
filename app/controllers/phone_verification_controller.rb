# frozen_string_literal: true

class PhoneVerificationController < ApplicationController
  include Authentication

  skip_before_action :authenticate_sway_user!

  rate_limit to: 10, within: 1.hour,
    name: "create_ip",
    by: -> { request.remote_ip },
    only: :create,
    if: -> { RateLimitConfig.enabled?(:phone_verify) },
    with: -> { render_rate_limited },
    store: ApplicationController::RATE_LIMIT_STORE
  rate_limit to: 10, within: 1.minute,
    name: "update_ip",
    by: -> { request.remote_ip },
    only: :update,
    if: -> { RateLimitConfig.enabled?(:phone_verify) },
    with: -> { render_rate_limited },
    store: ApplicationController::RATE_LIMIT_STORE
  rate_limit to: 5, within: 10.minutes,
    name: "update_phone",
    # @lat: [[phone-cache-hashing]]
    by: -> {
      # @type self: PhoneVerificationController
      PhoneCacheKey.digest(session[:phone])
    },
    only: :update,
    if: -> { RateLimitConfig.enabled?(:phone_verify) },
    with: -> { render_rate_limited },
    store: ApplicationController::RATE_LIMIT_STORE

  def create
    phone = phone_verification_params[:phone].to_s.normalize_phone
    if phone.length != 10
      return render json: {success: false, error: "Phone must be 10 digits."}, status: :unprocessable_content
    end

    phone_last4 = phone.last(4)

    if Sway::Settings.dev_login.skip_phone_verification
      session[:phone] = phone
      SwayLogging.info(
        "phone_verification.create_skipped",
        phone_last4: phone_last4
      )
      render json: {success: true}, status: :ok
    else
      SwayLogging.info(
        "phone_verification.create_requested",
        phone_last4: phone_last4
      )
      render json: {
               success:
                 send_phone_verification(
                   session,
                   phone
                 )
             },
        status: :ok
    end
  end

  def update
    phone = session[:phone].to_s.normalize_phone
    code = phone_verification_params[:code].to_s.strip
    if session[:phone].blank? || phone.length != 10 || code.blank?
      return render json: {success: false, error: "Invalid verification request."}, status: :unprocessable_content
    end

    # @lat: [[identity-and-access#Identity and access#The phone number is the account#A phone verified in this session confirms again without Twilio]]
    return render json: {success: true}, status: :ok if session[:verified_phone] == phone

    session_phone_last4 = phone.last(4)

    if Sway::Settings.dev_login.skip_phone_verification
      session[:phone] = phone
      session[:verified_phone] = phone
      approved = true

      SkipPhoneVerificationProvisioner.call(phone: phone)
    else
      approved = false
      verification_error = nil
      begin
        approved = verification_approved?(
          to: "+1#{phone}",
          code: code
        )
        SwayLogging.info(
          "phone_verification.update_result",
          phone_last4: session_phone_last4,
          approved: approved
        )
      rescue Twilio::REST::RestError => e
        # @lat: [[twilio-error-phone-redaction#Why Twilio error handling redacts recipient identifiers]]
        SwayLogging.warn(
          "phone_verification.update_failed",
          phone_last4: session_phone_last4,
          twilio_code: e.code
        )
        # @lat: [[identity-and-access#Identity and access#The phone number is the account#A verification-not-found reply has one safe browser outcome]]
        if e.code&.to_s == "20404" ||
            e.full_message.include?("VerificationCheck was not found")
          return render json: {success: false, error: "Code not found."}, status: :ok
        end
        verification_error = "code=#{e.code}, status=#{e.status_code}"
      rescue Twilio::REST::TwilioError => e
        # @lat: [[twilio-error-phone-redaction#Why a Twilio network failure is answered, not raised]]
        SwayLogging.warn(
          "phone_verification.update_failed",
          phone_last4: session_phone_last4,
          error_class: e.class.name
        )
        return render json: {success: false, error: "Could not check the code. Please try again."}, status: :ok
      end

      # @lat: [[twilio-error-phone-redaction#Why Twilio error handling redacts recipient identifiers]]
      raise Authentication::TwilioVerificationError, "Twilio verification check failed (#{verification_error})" if verification_error

      if approved
        # @lat: [[identity-and-access#Identity and access#The phone number is the account]]
        session[:verified_phone] = phone
      end
    end

    render json: {success: approved}, status: :ok
  end

  private

  def phone_verification_params
    params.require(:phone_verification).permit(:phone, :code)
  end
end
