# typed: true

# frozen_string_literal: true

module Users
  module Webauthn
    class SessionsController < ApplicationController
      extend T::Sig
      include Authentication

      rate_limit(to: 100, within: 1.minute)

      skip_before_action :authenticate_sway_user!

      before_action :verify_valid_phone, only: %i[create]

      def create
        user = User.find_by(phone:)

        if user&.has_sway_passkey?
          get_options =
            relying_party.options_for_authentication(
              allow_credentials:
                user.passkeys.map do |p|
                  { id: p.external_id, type: "public-key" }
                end,
              user_verification: "required",
            )

          session[:current_authentication] = {
            challenge: get_options.challenge,
            phone:,
          }

          render json: get_options
        elsif phone.present?
          if ENV.fetch("SKIP_PHONE_VERIFICATION", nil).present?
            session[:phone] = phone
            render json: { success: true }, status: :accepted
          else
            render json: {
                     success: send_phone_verification(session, phone),
                   },
                   status: :accepted
          end
        else
          render json: { success: false }, status: :unprocessable_content
        end
      end

      def callback
        
          current_authentication = session[:current_authentication]
          challenge = current_authentication&.dig("challenge") || current_authentication&.dig(:challenge)
          authentication_phone = current_authentication&.dig("phone") || current_authentication&.dig(:phone)

          if challenge.blank? || authentication_phone.blank?
            render json: {
                     success: false,
                     message: "Authentication session expired. Please try again.",
                   },
                   status: :unprocessable_content
            return
          end

          user = User.find_by(phone: authentication_phone)
          unless user
            render json: {
                     success: false,
                     message: "User not found for authentication.",
                   },
                   status: :unprocessable_content
            return
          end

          verified_webauthn_passkey, stored_passkey =
            relying_party.verify_authentication(
              public_key_credential_params,
              challenge,
              user_verification: true,
            ) do |webauthn_passkey|
              user
                .passkeys
                .where(
                  external_id: [
                    webauthn_passkey.id,
                    Base64.strict_encode64(webauthn_passkey.raw_id),
                  ],
                )
                .first
            end

          unless stored_passkey
            render json: {
                     success: false,
                     message: "Passkey not found for this account.",
                   },
                   status: :unprocessable_content
            return
          end

          stored_passkey.update!(
            sign_count: verified_webauthn_passkey.sign_count,
          )
          sign_in(user)

          session[:verified_phone] = user.phone
          if user.is_registration_complete
            route_component(legislators_path)
          else
            route_component(sway_registration_index_path)
          end
        rescue WebAuthn::Error => e
          render json: {
                   success: false,
                   message: "Verification failed: #{e.message}",
                 },
                  status: :unprocessable_content
        rescue ActionController::ParameterMissing => e
          render json: {
                   success: false,
                   message: "Invalid authentication payload: missing #{e.param}",
                 },
                 status: :unprocessable_content
        ensure
          session.delete(:current_authentication)
        
      end

      def destroy
        sign_out
      end

      private

      def session_params
        params.permit(:phone, :publicKeyCredential, :token)
      end

      def public_key_credential_params
        params.require(:publicKeyCredential)
      end

      sig { returns(T.nilable(String)) }
      def phone
        @phone ||= session_params[:phone]&.remove_non_digits
      end

      def verify_valid_phone
        return unless phone.blank? || phone&.size != 10

        redirect_to(root_path, errors: { phone: "Phone must be 10 digits." })
      end
    end
  end
end
