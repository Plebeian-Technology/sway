# frozen_string_literal: true

module Users
  module Webauthn
    # @lat: [[identity-and-access#Identity and access#The sign-in challenge says which ceremony to run#A missing stored passkey must stop verification before key access]]
    class UnknownPasskeyError < StandardError; end

    class SessionsController < ApplicationController
      include Authentication

      rate_limit to: 10, within: 5.minutes,
        by: -> { request.remote_ip },
        only: :create,
        if: -> { RateLimitConfig.enabled?(:sign_in) },
        with: -> { render_rate_limited },
        store: ApplicationController::RATE_LIMIT_STORE
      rate_limit to: 5, within: 5.minutes,
        # @lat: [[phone-cache-hashing]]
        by: -> { PhoneCacheKey.digest(session_params[:phone]) },
        only: :create,
        if: -> { RateLimitConfig.enabled?(:sign_in) },
        with: -> { render_rate_limited },
        store: ApplicationController::RATE_LIMIT_STORE

      skip_before_action :authenticate_sway_user!

      before_action :verify_valid_phone, only: %i[create]

      # @lat: [[identity-and-access#The sign-in challenge says which ceremony to run]]
      def create
        user = User.find_by(phone:)
        phone_last4 = phone&.last(4)

        if user&.has_sway_passkey?
          get_options =
            relying_party.options_for_authentication(
              allow_credentials:
                user.passkeys.map do |p|
                  {id: p.external_id, type: "public-key"}
                end,
              user_verification: "required"
            )

          session[:current_authentication] = {
            challenge: get_options.challenge,
            phone:
          }

          SwayLogging.info(
            "webauthn.session.create_challenge",
            user_id: user.id,
            phone_last4: phone_last4,
            passkey_count: user.passkeys.count
          )
          render json: {flow: "passkey", options: get_options}
        elsif phone.present?
          return render_rate_limited if sms_verification_rate_limited?(phone)

          if Sway::Settings.dev_login.skip_phone_verification
            session[:phone] = phone
            SwayLogging.info(
              "webauthn.session.phone_verification_skipped",
              phone_last4: phone_last4
            )
            render json: {flow: "sms", success: true}
          else
            SwayLogging.info(
              "webauthn.session.phone_verification_requested",
              phone_last4: phone_last4
            )
            render json: {
              flow: "sms",
              success: send_phone_verification(session, phone)
            }
          end
        else
          render json: {success: false}, status: :unprocessable_content
        end
      end

      # @lat: [[identity-and-access#The sign-in challenge says which ceremony to run]]
      def discoverable_challenge
        get_options =
          relying_party.options_for_authentication(
            allow_credentials: [],
            user_verification: "required"
          )

        session[:discoverable_authentication] = {
          challenge: get_options.challenge
        }

        render json: {flow: "passkey", options: get_options}
      end

      # @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Discoverable callback resolves the credential owner]]
      def discoverable_callback
        user = nil
        challenge =
          session.dig(:discoverable_authentication, "challenge") ||
          session.dig(:discoverable_authentication, :challenge)

        if challenge.blank?
          SwayLogging.warn("webauthn.session.discoverable_challenge_missing")
          redirect_to root_path, alert: "Authentication session expired. Please try again."
          return
        end

        verified_webauthn_passkey, stored_passkey =
          relying_party.verify_authentication(
            public_key_credential_params,
            challenge,
            user_verification: true
          ) do |webauthn_passkey|
            passkey = Passkey
              .where(
                external_id: [
                  webauthn_passkey.id,
                  Base64.strict_encode64(webauthn_passkey.raw_id)
                ]
              )
              .first
            passkey || raise(UnknownPasskeyError)
          end

        unless stored_passkey
          redirect_to root_path, alert: "Passkey not recognized. Please try again."
          return
        end

        user = stored_passkey.user
        stored_passkey.update!(
          sign_count: verified_webauthn_passkey.sign_count,
          last_used_at: Time.current
        )
        sign_in(user)
        SwayLogging.info(
          "webauthn.session.discoverable_authenticated",
          user_id: user.id,
          passkey_id: stored_passkey.id
        )

        session[:verified_phone] = user.phone
        if user.registered?
          # @lat: [[low-friction-voting#Reconciliation on registration and sign-in]]
          reconciliation = PendingVoteReconciliationService.call(user: user, cookies: cookies)
          if reconciliation[:success] && reconciliation[:bill].present?
            redirect_to bill_path(reconciliation[:bill])
          else
            redirect_to feed_path
          end
        else
          redirect_to sway_registration_index_path
        end
      rescue UnknownPasskeyError
        session.delete(:webauthn_challenge)
        redirect_to root_path, alert: "Passkey not recognized. Please try again."
      rescue WebAuthn::Error => e
        SwayLogging.log_exception(
          "webauthn.session.discoverable_verification_failed",
          exception: e,
          level: :warn,
          user_id: user&.id
        )
        redirect_to root_path, alert: "Verification failed: #{e.message}"
      rescue ActionController::ParameterMissing => e
        SwayLogging.log_exception(
          "webauthn.session.discoverable_invalid_payload",
          exception: e,
          level: :warn,
          user_id: user&.id
        )
        redirect_to root_path, alert: "Invalid authentication payload: missing #{e.param}"
      ensure
        session.delete(:discoverable_authentication)
      end

      def callback
        user = nil
        current_authentication = session[:current_authentication]
        challenge =
          current_authentication&.dig("challenge") ||
          current_authentication&.dig(:challenge)
        authentication_phone =
          current_authentication&.dig("phone") ||
          current_authentication&.dig(:phone)

        if challenge.blank? || authentication_phone.blank?
          SwayLogging.warn("webauthn.session.challenge_missing")
          redirect_to root_path, alert: "Authentication session expired. Please try again."
          return
        end

        user = User.find_by(phone: authentication_phone)
        unless user
          SwayLogging.warn(
            "webauthn.session.user_not_found",
            phone_last4: authentication_phone.to_s.last(4)
          )
          redirect_to root_path, alert: "User not found for authentication."
          return
        end

        verified_webauthn_passkey, stored_passkey =
          relying_party.verify_authentication(
            public_key_credential_params,
            challenge,
            user_verification: true
          ) do |webauthn_passkey|
            passkey = user
              .passkeys
              .where(
                external_id: [
                  webauthn_passkey.id,
                  Base64.strict_encode64(webauthn_passkey.raw_id)
                ]
              )
              .first
            passkey || raise(UnknownPasskeyError)
          end

        unless stored_passkey
          redirect_to root_path, alert: "Passkey not found for this account."
          return
        end

        stored_passkey.update!(
          sign_count: verified_webauthn_passkey.sign_count,
          last_used_at: Time.current
        )
        sign_in(user)
        SwayLogging.info(
          "webauthn.session.authenticated",
          user_id: user.id,
          passkey_id: stored_passkey.id
        )

        session[:verified_phone] = user.phone
        if user.registered?
          # @lat: [[low-friction-voting#Reconciliation on registration and sign-in]]
          reconciliation = PendingVoteReconciliationService.call(user: user, cookies: cookies)
          if reconciliation[:success] && reconciliation[:bill].present?
            redirect_to bill_path(reconciliation[:bill])
          else
            redirect_to feed_path
          end
        else
          redirect_to sway_registration_index_path
        end
      rescue UnknownPasskeyError
        session.delete(:webauthn_challenge)
        redirect_to root_path, alert: "Passkey not found for this account."
      rescue WebAuthn::Error => e
        SwayLogging.log_exception(
          "webauthn.session.verification_failed",
          exception: e,
          level: :warn,
          user_id: user&.id,
          phone_last4: authentication_phone.to_s.last(4)
        )
        redirect_to root_path, alert: "Verification failed: #{e.message}"
      rescue ActionController::ParameterMissing => e
        SwayLogging.log_exception(
          "webauthn.session.invalid_payload",
          exception: e,
          level: :warn,
          user_id: user&.id
        )
        redirect_to root_path, alert: "Invalid authentication payload: missing #{e.param}"
      ensure
        session.delete(:current_authentication)
      end

      def destroy
        sign_out
        flash[:notice] = "Successfully signed out."
        # @lat: [[client-caches-and-identity#Client caches and identity#Why sign-out does not clear them by itself]]
        redirect_to root_path, inertia: {clear_history: true}
      end

      private

      def session_params
        params.permit(:phone, :publicKeyCredential, :token)
      end

      def public_key_credential_params
        params.require(:publicKeyCredential)
      end

      def phone
        @phone ||= session_params[:phone]&.normalize_phone
      end

      def verify_valid_phone
        return unless phone.blank? || phone&.size != 10

        redirect_to(root_path, inertia: {errors: {phone: "Phone must be 10 digits."}})
      end
    end
  end
end
