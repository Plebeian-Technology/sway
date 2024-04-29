# typed: true

# frozen_string_literal: true

class Users::Webauthn::SessionsController < ApplicationController
  extend T::Sig

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
      render json: { errors: ['User not found.'] }, status: :unprocessable_entity
    end
  end

  def callback
    user = User.find_by(phone: session.dig(:current_authentication, 'phone'))
    raise "user #{session.dig(:current_authentication, 'phone')} never initiated sign up" unless user

    begin
      verified_webauthn_passkey, stored_passkey = relying_party.verify_authentication(
        public_key_credential_params,
        session.dig(:current_authentication, 'challenge'),
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
    params.require(:session).permit(:phone, :publicKeyCredential)
  end

  <<~DOC
    #<ActionController::Parameters {"type"=>"public-key", "id"=>"SjW_7InKkSYEPjiWQ8jbtOB3FHwP5gLpFbcqikBLPYY", "rawId"=>"SjW_7InKkSYEPjiWQ8jbtOB3FHwP5gLpFbcqikBLPYY", "authenticatorAttachment"=>"platform", "response"=>{"clientDataJSON"=>"eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoibkdJb1pFTi1hdnlpTm5OcG0wNVJLN2RkVWpJT0lFZXNiZENWbE16d3FDWSIsIm9yaWdpbiI6Imh0dHBzOi8vbG9jYWxob3N0OjMwMDAiLCJjcm9zc09yaWdpbiI6ZmFsc2V9", "authenticatorData"=>"SZYN5YgOjGh0NBcPZHZgW4_krrmihjLHmVzzuoMdl2MFAAAAAA", "signature"=>"MEUCIC23BEtRrTmqc5nAkA5pJz2cZVRWFsvvA94IJCEoq_kBAiEAl4b5h6bkfBXlyq6usmHJ_qp8-XeNwBsEtjgBTaqP808", "userHandle"=>"B6MWXma3yVQJPuM3L1YVevpFWC0FZykt1U8LBPX-b040JYi2JW9_4r4wOGpvtC4zH02IOlbaSPXz4aO8glGyag"}, "clientExtensionResults"=>{}} permitted: false>
  DOC
  def public_key_credential_params
    # params.require(:session).require(:publicKeyCredential).permit(:type, :id, :rawId, :authenticatorAttachment,
    #                                                               :response, :userHandle, :clientExtensionResults)
    params.require(:session).require(:publicKeyCredential)
  end
end
