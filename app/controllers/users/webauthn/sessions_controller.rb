# typed: true

# frozen_string_literal: true

class Users::Webauthn::SessionsController < ApplicationController
  def new
  end

  def create
    user = User.find_by(phone: session_params[:phone])

    if user
      get_options = relying_party.options_for_authentication(
        allow: user.passkeys.pluck(:external_id),
        user_verification: 'required'
      )

      session[:current_authentication] = { challenge: get_options.challenge, phone: session_params[:phone] }

      render json: get_options
    else
      render json: { errors: ["Username doesn't exist"] }, status: :unprocessable_entity
    end
  end

  def callback
    user = User.find_by(phone: session[:current_authentication]['phone'])
    raise "user #{session[:current_authentication]['phone']} never initiated sign up" unless user

    begin
      verified_webauthn_passkey, stored_passkey = relying_party.verify_authentication(
        params,
        session[:current_authentication]['challenge'],
        user_verification: true
      ) do |webauthn_passkey|
        user.passkeys.find_by(external_id: Base64.strict_encode64(webauthn_passkey.raw_id))
      end

      stored_passkey.update!(sign_count: verified_webauthn_passkey.sign_count)
      sign_in(user)

      render json: user.to_builder.target!, status: :ok
    rescue WebAuthn::Error => e
      render json: "Verification failed: #{e.message}", status: :unprocessable_entity
    ensure
      session.delete(:current_authentication)
    end
  end

  def destroy
    sign_out

    redirect_to root_path
  end

  private

  def session_params
    params.require(:session).permit(:phone)
  end
end
