# typed: true

# frozen_string_literal: true

class Users::Webauthn::RegistrationController < ApplicationController
  extend T::Sig

  before_action :test_recaptcha, only: [:create]
  skip_before_action :redirect_if_no_current_user

  def create
    user = User.find_or_initialize_by(
      phone: session[:verified_phone]
    )

    user.is_phone_verified = session[:verified_phone] == session[:phone]

    if user.is_phone_verified
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
    else
      render json: { success: false, message: 'Please confirm your phone number first.' }, status: :ok
    end
  end

  def callback
    user = User.find_by(phone: session[:verified_phone])
    if user.present?
      user.update!(user_attributes)
    else
      user = User.create!(user_attributes)
    end

    begin
      webauthn_passkey = relying_party.verify_registration(
        params,
        challenge,
        user_verification: true
      )

      passkey = Passkey.new(
        user:,
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

  def user_attributes
    session.dig(:current_registration, 'user_attributes')
  end

  def challenge
    session.dig(:current_registration, 'challenge')
  end

  private

  sig { returns(ActionController::Parameters) }
  def registration_params
    params.require(:registration).permit(:passkey_label, :token)
  end
end
