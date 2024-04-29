# typed: true

# frozen_string_literal: true

class Users::Webauthn::PasskeysController < ApplicationController
  def create
    create_options = relying_party.options_for_registration(
      user: {
        id: current_user&.webauthn_id,
        name: current_user&.email
      },
      exclude: current_user&.passkeys&.pluck(:external_id),
      authenticator_selection: { user_verification: 'required' }
    )

    session[:current_registration] = { challenge: create_options.challenge }

    render json: create_options
  end

  def callback
    webauthn_passkey = relying_party.verify_registration(
      params,
      session.dig(:current_registration, :challenge),
      user_verification: true
    )

    passkey = current_user&.passkeys&.find_or_initialize_by(
      external_id: Base64.strict_encode64(webauthn_passkey.raw_id)
    )

    if passkey&.update(
      label: params[:passkey_label],
      public_key: webauthn_passkey.public_key,
      sign_count: webauthn_passkey.sign_count
    )
      render json: current_user&.to_builder&.target!, status: :ok
    else
      render json: "Couldn't add your Security Key", status: :unprocessable_entity
    end
  rescue WebAuthn::Error => e
    render json: "Verification failed: #{e.message}", status: :unprocessable_entity
  ensure
    session.delete(:current_registration)
  end

  def destroy
    current_user&.passkeys&.destroy(params[:id]) if current_user&.can_delete_passkeys?

    redirect_to root_path
  end
end
