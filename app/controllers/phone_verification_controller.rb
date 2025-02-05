# frozen_string_literal: true
# typed: true

# https://www.twilio.com/docs/verify/sms
# https://www.twilio.com/docs/verify/quickstarts/python-flask
class PhoneVerificationController < ApplicationController
  include Authentication
  extend T::Sig

  before_action :set_twilio_client
  skip_before_action :redirect_if_no_current_user

  def create
    if Rails.env.production?
      render json: {success: send_phone_verification(session, phone_verification_params[:phone])}, status: :ok
    else
      session[:phone] = phone_verification_params[:phone]
      render json: {success: true}, status: :ok
    end
  end

  def update
    if Rails.env.production?
      verification_check = @client.verify
        .v2
        .services(service_sid)
        .verification_checks
        .create(to: "+1#{session[:phone]}", code: phone_verification_params[:code])

      approved = verification_check&.status == "approved"

      if approved
        # Do NOT create a user here
        # there exists a race condition where a phone is verified
        # and an attacker creates a passkey on another device using the verified phone
        # if we create a user with a verified phone here
        session[:verified_phone] = session[:phone]
      end
    else
      session[:verified_phone] = session[:phone]
      approved = true
    end

    render json: {success: approved}, status: :ok
  end

  private

  def set_twilio_client
    @client ||= Twilio::REST::Client.new(account_sid, auth_token)
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

  sig { returns(ActionController::Parameters) }
  def phone_verification_params
    params.require(:phone_verification).permit(:phone, :code)
  end
end
