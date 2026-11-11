# frozen_string_literal: true

module Users
  # @lat: [[email-verifications-controller-notes#Why destroy also clears a stale unverified email]]
  class EmailVerificationsController < ApplicationController
    include Authentication

    rate_limit to: 10, within: 1.hour,
      name: "create_ip",
      by: -> { request.remote_ip },
      only: :create,
      if: -> { RateLimitConfig.enabled?(:email_verify) },
      with: -> { render_rate_limited },
      store: ApplicationController::RATE_LIMIT_STORE
    rate_limit to: 3, within: 1.hour,
      name: "create_email",
      by: -> { EmailCacheKey.digest(email_verification_params[:email]) },
      only: :create,
      if: -> { RateLimitConfig.enabled?(:email_verify) },
      with: -> { render_rate_limited },
      store: ApplicationController::RATE_LIMIT_STORE
    rate_limit to: 10, within: 1.hour,
      name: "update_ip",
      by: -> { request.remote_ip },
      only: :update,
      if: -> { RateLimitConfig.enabled?(:email_verify) },
      with: -> { render_rate_limited },
      store: ApplicationController::RATE_LIMIT_STORE
    rate_limit to: 10, within: 1.hour,
      name: "update_user",
      by: -> { current_user.id },
      only: :update,
      if: -> { RateLimitConfig.enabled?(:email_verify) },
      with: -> { render_rate_limited },
      store: ApplicationController::RATE_LIMIT_STORE

    # @lat: [[email-verifications-controller-notes#Why the pending address lives only in the session]]
    def create
      email = email_verification_params[:email].to_s.strip.downcase
      unless URI::MailTo::EMAIL_REGEXP.match?(email)
        return respond_failure(:email, "Enter a valid email address.")
      end

      if send_email_verification(email)
        session[:pending_email] = email
        session[:pending_email_attempts] = 0
        respond_success("Confirmation code sent! Check your email.")
      else
        respond_failure(:email, "Failed to send a verification code. Please try again.")
      end
    end

    # @lat: [[email-verifications-controller-notes#Why the pending address lives only in the session]]
    def update
      pending = session[:pending_email].to_s
      if pending.blank?
        return respond_failure(:code, "Start over and re-enter your email address.")
      end

      approved = false
      if Sway::Settings.dev_login.skip_phone_verification
        approved = true
      else
        # @lat: [[twilio-error-phone-redaction#Why PhoneVerificationController.update reads e.full_message only to branch]]
        verification_error = nil
        begin
          approved = verification_approved?(to: pending, code: email_verification_params[:code].to_s)
        rescue Twilio::REST::RestError => e
          SwayLogging.warn("users.email_verification.check_failed", twilio_code: e.code)
          if e.code&.to_s == "20404" || e.full_message.include?("VerificationCheck was not found")
            return respond_failure(:code, "That code has expired. Start over to request a new one.")
          end
          verification_error = "code=#{e.code}, status=#{e.status_code}"
        end
        if verification_error
          raise Authentication::TwilioVerificationError,
            "Twilio email verification check failed (#{verification_error})"
        end
      end

      unless approved
        attempts = session[:pending_email_attempts].to_i + 1
        if attempts >= 5
          session.delete(:pending_email)
          session.delete(:pending_email_attempts)
        else
          session[:pending_email_attempts] = attempts
        end
        return respond_failure(:code, "That code did not match. Please try again.")
      end

      begin
        current_user.update!(email: pending, is_email_verified: true)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        return respond_failure(:email, "That email address cannot be used. Start over with a different one.")
      end
      session.delete(:pending_email)
      session.delete(:pending_email_attempts)
      respond_success("Email verified!")
    end

    # @lat: [[email-verifications-controller-notes#Why destroy also clears a stale unverified email]]
    def destroy
      session.delete(:pending_email)
      session.delete(:pending_email_attempts)
      if current_user.email.present? && !current_user.is_email_verified
        current_user.update(email: nil, is_email_verified: false)
      end
      respond_success("Email verification reset.")
    end

    private

    def respond_success(notice)
      redirect_or_json(bill_target, flash_message: notice)
    end

    # @lat: [[email-verifications-controller-notes#Why respond_failure supports both response formats]]
    def respond_failure(field, message)
      if mobile_api_request?
        render_error(
          code: "email_verification_failed",
          message: message,
          status: :unprocessable_content,
          details: {field => message}
        )
      else
        redirect_to(bill_target, inertia: {errors: {field => message}})
      end
    end

    # @lat: [[email-verifications-controller-notes#Why the redirect target carries with: "legislator,address"]]
    def bill_target
      bill_id = email_verification_params[:bill_id].presence || params[:bill_id].presence
      if bill_id
        bill_path(bill_id, {with: "legislator,address"})
      else
        root_path
      end
    end

    def email_verification_params
      # @lat: [[email-verifications-controller-notes#Why email_verification_params uses fetch, not require]]
      params.fetch(:email_verification, {}).permit(:email, :code, :bill_id)
    end
  end
end
