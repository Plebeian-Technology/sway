# typed: true

# frozen_string_literal: true

class Users::Webauthn::RegistrationController < ApplicationController
  extend T::Sig

  before_action :test_recaptcha, only: [:create]

  def create
    user = User.find_or_initialize_by(
      phone: session[:verified_phone]
    )

    user.is_phone_verified = session[:verified_phone] == session[:phone]

    unless user.is_phone_verified
      render json: { success: false, message: "Please confirm your phone number first." }, status: :ok
    else
      create_options = relying_party.options_for_registration(
        user: {
          name: session[:verified_phone],
          id: user.webauthn_id
        },
        authenticator_selection: { user_verification: 'required' }
      )

      if user.valid?
        session[:current_registration] = { challenge: create_options.challenge, user_attributes: user.attributes }

        render json: create_options
      else
        render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end

  def callback
    user = User.find_by(phone: session[:verified_phone])
    if user.present?
      user.update!(session[:current_registration]['user_attributes'])
    else
      user = User.create!(session[:current_registration]['user_attributes'])
    end


    begin
      webauthn_passkey = relying_party.verify_registration(
        params,
        session[:current_registration]['challenge'],
        user_verification: true
      )

      passkey = user.passkeys.build(
        external_id: Base64.strict_encode64(webauthn_passkey.raw_id),
        label: params[:passkey_label],
        public_key: webauthn_passkey.public_key,
        sign_count: webauthn_passkey.sign_count
      )

      if passkey.save
        sign_in(user)

        T.unsafe(self).route_registration
      else
        render json: {
          success: false,
          message: "Couldn't register your Passkey"
        }, status: :unprocessable_entity
      end
    rescue WebAuthn::Error => e
      render json: {
        success: false,
        message: "Verification failed: #{e.message}"
      }, status: :unprocessable_entity
    ensure
      session.delete(:current_registration)
    end
  end

  private

  sig { returns(ActionController::Parameters) }
  def registration_params
    params.require(:registration).permit(:passkey_label)
  end
end
