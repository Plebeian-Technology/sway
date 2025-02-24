# typed: true

class UserEmailConfirmationController < ApplicationController
  include Authentication
  extend T::Sig

  before_action :set_twilio_client

  def create
    if ENV.fetch("SKIP_PHONE_VERIFICATION", nil).present? || send_email_verification(session, email_verification_params[:email])
      session[:email] = email_verification_params[:email]
    end

    if session[:email].present?
      current_user.update(email: session[:email])
      flash[:notice] = "Confirmation Email Sent!"
    else
      flash[:error] = "Failed to send verification email. Please try again."
    end

    redirect_to(email_verification_params[:redirect_to], only_path: true)
  end

  def update
    approved = false
    if ENV.fetch("SKIP_PHONE_VERIFICATION", nil).present?
      approved = true
    else
      verification_check = @client.verify
        .v2
        .services(service_sid)
        .verification_checks
        .create(to: session[:email], code: email_verification_params[:code])

      approved = verification_check&.status == "approved"
    end
    current_user.update(email: session[:email], is_email_verified: approved)

    if approved
      flash[:notice] = "Email Verified!"
    else
      flash[:error] = "We could verify your email address. Please try again."
    end

    redirect_to(email_verification_params[:redirect_to], only_path: true)
  end

  def destroy
    current_user.update(email: nil, is_email_verified: false)
    flash[:notice] = "Email Verification Reset"
    render json: {
      success: true
    }
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
  def email_verification_params
    params.require(:user_email_confirmation).permit(:email, :code, :redirect_to)
  end

  sig { returns(User) }
  def current_user
    T.cast(super, User)
  end
end
