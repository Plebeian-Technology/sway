# typed: true

# frozen_string_literal: true

module Users
  module Webauthn
    class SessionsController < ApplicationController
      extend T::Sig
      include Authentication

      skip_before_action :redirect_if_no_current_user

      def create
        user = User.find_by(phone:)

        if user&.has_passkey?
          get_options = relying_party.options_for_authentication(
            allow: user.passkeys.pluck(:external_id),
            user_verification: "required"
          )

          session[:current_authentication] = {challenge: get_options.challenge, phone:}

          render json: get_options
        elsif phone.present?
          if Rails.env.production?
            render json: {success: send_phone_verification(session, phone)}, status: :accepted
          else
            session[:phone] = phone
            render json: {success: true}, status: :accepted
          end
        else
          render json: {success: false}, status: :unprocessable_entity
        end
      end

      def callback
        user = User.find_by(phone: session.dig(:current_authentication, "phone"))
        raise "user #{session.dig(:current_authentication, "phone")} never initiated sign up" unless user

        begin
          verified_webauthn_passkey, stored_passkey = relying_party.verify_authentication(
            public_key_credential_params,
            session.dig(:current_authentication, "challenge"),
            user_verification: true
          ) do |webauthn_passkey|
            user.passkeys.find_by(external_id: Base64.strict_encode64(webauthn_passkey.raw_id))
          end

          stored_passkey.update!(sign_count: verified_webauthn_passkey.sign_count)
          sign_in(user)

          session[:verified_phone] = user.phone
          if user.is_registration_complete
            SwayRoutes::LEGISLATORS
          else
            SwayRoutes::REGISTRATION
          end
        rescue WebAuthn::Error => e
          render json: {
            success: false,
            message: "Verification failed: #{e.message}"
          }, status: :unprocessable_entity
        ensure
          session.delete(:current_authentication)
        end
      end

      def destroy
        sign_out

        # redirect_to root_path
      end

      private

      def session_params
        params.permit(:phone, :publicKeyCredential, :token)
      end

      def public_key_credential_params
        # params.require(:publicKeyCredential).permit(:type, :id, :rawId, :authenticatorAttachment,
        #                                                               :response, :userHandle, :clientExtensionResults)
        params.require(:publicKeyCredential)
      end

      sig { returns(T.nilable(String)) }

      def phone
        session_params[:phone]&.remove_non_digits
      end
    end
  end
end
