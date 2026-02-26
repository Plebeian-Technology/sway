# typed: true

# frozen_string_literal: true

module Users
  module Webauthn
    class RegistrationController < ApplicationController
      extend T::Sig

      rate_limit(to: 100, within: 1.minute)

      skip_before_action :authenticate_sway_user!

      def create
        user = User.find_or_initialize_by(phone: session[:verified_phone])

        user.is_phone_verified = session[:verified_phone] == session[:phone]

        if user.is_phone_verified
          create_options =
            relying_party.options_for_registration(
              user: {
                name: session[:verified_phone],
                id: user.webauthn_id,
              },
              authenticator_selection: {
                user_verification: "required",
              },
              exclude: user.passkeys.pluck(:external_id),
            )

          if user.valid?
            session[:current_registration] = {
              challenge: create_options.challenge,
              user_attributes: user.attributes,
            }

            render json: create_options
          else
            render json: {
                     errors: user.errors.full_messages,
                   },
                   status: :unprocessable_content
          end
        else
          render json: {
                   success: false,
                   message: "Please confirm your phone number first.",
                 },
                 status: :ok
        end
      end

      def callback
        current_registration = session[:current_registration]
        registration_challenge =
          current_registration&.dig("challenge") ||
            current_registration&.dig(:challenge)
        attributes =
          current_registration&.dig("user_attributes") ||
            current_registration&.dig(:user_attributes)
        verified_phone = session[:verified_phone]

        if registration_challenge.blank? || verified_phone.blank?
          render json: {
                   success: false,
                   message: "Registration session expired. Please try again.",
                 },
                 status: :unprocessable_content
          return
        end

        user = User.find_or_initialize_by(phone: verified_phone)
        user.assign_attributes(sanitized_user_attributes(attributes, verified_phone))

        webauthn_passkey =
          relying_party.verify_registration(
            params,
            registration_challenge,
            user_verification: true,
          )

        user.save!

        passkey =
          Passkey.new(
            user:,
            external_id: webauthn_passkey.id,
            label: params[:passkey_label],
            public_key: webauthn_passkey.public_key,
            sign_count: webauthn_passkey.sign_count,
          )

        if passkey.save
          sign_in(user)

          route_component(SwayRoutes::REGISTRATION)
        else
          render json: {
                   success: false,
                   message: "Couldn't register your Passkey",
                 },
                 status: :unprocessable_content
        end
        rescue WebAuthn::Error => e
          render json: {
                   success: false,
                   message: "Verification failed: #{e.message}",
                 },
                 status: :unprocessable_content
        rescue ActiveRecord::RecordInvalid => e
          render json: {
                   success: false,
                   errors: e.record.errors.full_messages,
                 },
                 status: :unprocessable_content
        ensure
          session.delete(:current_registration)
      end

      private

      sig do
        params(attributes: T.untyped, verified_phone: String).returns(T::Hash[Symbol, T.untyped])
      end
      def sanitized_user_attributes(attributes, verified_phone)
        raw_attributes = attributes.is_a?(Hash) ? attributes : {}

        {
          phone: verified_phone,
          email: read_attribute(raw_attributes, "email"),
          full_name: read_attribute(raw_attributes, "full_name"),
          is_phone_verified: read_attribute(raw_attributes, "is_phone_verified"),
          is_admin: read_attribute(raw_attributes, "is_admin"),
          is_email_verified: read_attribute(raw_attributes, "is_email_verified"),
          is_registered_to_vote:
            read_attribute(raw_attributes, "is_registered_to_vote"),
          is_registration_complete:
            read_attribute(raw_attributes, "is_registration_complete"),
          registration_status:
            read_attribute(raw_attributes, "registration_status"),
        }.compact
      end

      sig { params(attributes: T::Hash[T.untyped, T.untyped], key: String).returns(T.untyped) }
      def read_attribute(attributes, key)
        return attributes[key] if attributes.key?(key)

        attributes[key.to_sym]
      end

      sig { returns(ActionController::Parameters) }
      def registration_params
        params.permit(:passkey_label, :token)
      end
    end
  end
end
