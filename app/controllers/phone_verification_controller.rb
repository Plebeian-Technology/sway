# frozen_string_literal: true
# typed: true

# https://www.twilio.com/docs/verify/sms
# https://www.twilio.com/docs/verify/quickstarts/python-flask
class PhoneVerificationController < ApplicationController
    include Authentication
    extend T::Sig

    before_action :set_twilio_client
    skip_before_action :authenticate_user!

    def create
        if ENV.fetch("SKIP_PHONE_VERIFICATION", nil).present?
            session[:phone] = phone_verification_params[:phone]
            render json: { success: true }, status: :ok
        else
            render json: { success: send_phone_verification(session, phone_verification_params[:phone]) }, status: :ok
        end
    end

    def update
        if ENV.fetch("SKIP_PHONE_VERIFICATION", nil).present?
            session[:verified_phone] = session[:phone]
            approved = true
            u =
                User.find_or_create_by(
                    phone: session[:phone],
                    email: "#{session[:phone]}@sway.vote",
                    full_name: ENV.fetch("DEFAULT_USER_FULL_NAME").split("+").join(" "),
                )
            u.update(
                phone: session[:phone],
                is_admin: true,
                is_email_verified: true,
                is_phone_verified: true,
                is_registered_to_vote: true,
                is_registration_complete: true,
            )
            a =
                Address.find_or_create_by(
                    city: ENV.fetch("DEFAULT_CITY"),
                    postal_code: ENV.fetch("DEFAULT_REGION_CODE"),
                    region_code: ENV.fetch("DEFAULT_POSTAL_CODE"),
                    street: ENV.fetch("DEFAULT_STREET").split("+").join(" "),
                    latitude: ENV.fetch("DEFAULT_LATITUDE").to_f,
                    longitude: ENV.fetch("DEFAULT_LONGITUDE").to_f,
                )
            UserAddress.find_or_create_by(user: u, address: a)
        else
            verification_check =
                @client
                    .verify
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
        end

        render json: { success: approved }, status: :ok
    end

    private

    def set_twilio_client
        @set_twilio_client ||= Twilio::REST::Client.new(account_sid, auth_token)
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
