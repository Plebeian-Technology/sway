# frozen_string_literal: true

require_relative "../../users/webauthn/sessions_controller"

module Api
  module V1
    # @lat: [[passkey-only-sms-bootstrap#Why sign-in accepts only a passkey]]
    class SessionsController < BaseController
      include RelyingParty

      # @lat: [[phone-verification-rate-limits#Why the sign-in challenge throttles two ways]]
      rate_limit to: 10, within: 5.minutes,
        name: "challenge_ip",
        by: -> { request.remote_ip },
        only: :challenge,
        if: -> { RateLimitConfig.enabled?(:sign_in) },
        with: -> {
          # @type self: Api::V1::SessionsController
          response.set_header("Retry-After", 5.minutes.to_i.to_s)
          render_error(code: "rate_limited", message: "Too many sign-in attempts", status: :too_many_requests)
        },
        store: ApplicationController::RATE_LIMIT_STORE
      rate_limit to: 5, within: 5.minutes,
        name: "challenge_phone_ip",
        # @lat: [[phone-cache-hashing]]
        by: -> { "#{PhoneCacheKey.digest(params.dig(:session, :phone))}:#{request.remote_ip}" },
        only: :challenge,
        if: -> { RateLimitConfig.enabled?(:sign_in) },
        with: -> {
          # @type self: Api::V1::SessionsController
          response.set_header("Retry-After", 5.minutes.to_i.to_s)
          render_error(code: "rate_limited", message: "Too many attempts for this number", status: :too_many_requests)
        },
        store: ApplicationController::RATE_LIMIT_STORE

      def public_endpoint?
        %w[challenge discoverable_challenge callback].include?(action_name)
      end

      # @lat: [[decoy-challenge-non-disclosure#How the web sign-in flow (Users::Webauthn::SessionsController) achieves the same non-disclosure]]
      def challenge
        phone = params.require(:session).permit(:phone)[:phone].to_s.normalize_phone
        user = User.find_by(phone: phone)

        unless user&.has_sway_passkey?
          SwayLogging.info(
            "api_v1.sessions.challenge_flow",
            flow: "sms",
            phone_last4: phone.last(4)
          )
          return render json: {flow: "sms"}
        end

        options = relying_party.options_for_authentication(
          allow_credentials: user.passkeys.map { |p| {id: p.external_id, type: "public-key"} },
          user_verification: "required"
        )
        challenge_id = SecureRandom.hex(16)
        Rails.cache.write(
          "webauthn:challenge:#{challenge_id}",
          {challenge: options.challenge, phone: phone},
          expires_in: 5.minutes
        )

        SwayLogging.info(
          "api_v1.sessions.challenge_flow",
          flow: "passkey",
          phone_last4: phone.last(4),
          passkey_count: user.passkeys.count
        )

        # @lat: [[webauthn-camelcase-response-shape#Why mobile WebAuthn responses keep the spec's camelCase shape]]
        render json: {flow: "passkey", challenge_id: challenge_id, options: options.as_json}
      end

      # @lat: [[decoy-challenge-non-disclosure#How the web sign-in flow (Users::Webauthn::SessionsController) achieves the same non-disclosure]]
      def discoverable_challenge
        options = relying_party.options_for_authentication(
          allow_credentials: [],
          user_verification: "required"
        )
        challenge_id = SecureRandom.hex(16)
        Rails.cache.write(
          "webauthn:challenge:#{challenge_id}",
          {challenge: options.challenge, phone: nil},
          expires_in: 5.minutes
        )
        render json: options.as_json.merge(challenge_id: challenge_id)
      end

      def callback
        permit_credential = {}
        # @type var permit_credential: Hash[Symbol, untyped]
        p = params.require(:session).permit(:challenge_id, :platform, credential: permit_credential)
        cache_key = "webauthn:challenge:#{p[:challenge_id]}"
        cached = Rails.cache.read(cache_key)
        unless cached
          return render_error(
            code: "invalid_challenge",
            message: "Challenge expired or missing",
            status: :unauthorized
          )
        end

        # @lat: [[decoy-challenge-non-disclosure#How the web sign-in flow (Users::Webauthn::SessionsController) achieves the same non-disclosure]]
        user =
          if cached[:phone].present?
            User.find_by(phone: cached[:phone])
          else
            user_from_credential(p[:credential])
          end
        unless user&.has_sway_passkey?
          return render_error(
            code: "invalid_credentials",
            message: "User not found",
            status: :unauthorized
          )
        end

        log_passkey_client_origin(p[:credential])

        verified, stored_passkey = relying_party.verify_authentication(
          credential_for_verify(p[:credential]),
          cached[:challenge],
          user_verification: true
        ) do |webauthn_passkey|
          external_ids = [webauthn_passkey.id]
          if webauthn_passkey.respond_to?(:raw_id) && webauthn_passkey.raw_id
            external_ids << Base64.strict_encode64(webauthn_passkey.raw_id)
          end
          user.passkeys.find_by(external_id: external_ids) || raise(Users::Webauthn::UnknownPasskeyError)
        end

        unless stored_passkey
          return render_error(
            code: "invalid_credentials",
            message: "Passkey not found for this account",
            status: :unauthorized
          )
        end

        # @lat: [[passkey-only-sms-bootstrap#Why the sign-in challenge is deleted inside the callback transaction]]
        User.transaction do
          Rails.cache.delete(cache_key)
          stored_passkey.update!(
            sign_count: verified.sign_count,
            last_used_at: Time.current
          )
          issue_bearer_token(user, platform: p[:platform])
        end
      rescue WebAuthn::Error, Users::Webauthn::UnknownPasskeyError
        Rails.cache.delete(cache_key) if cache_key
        render_error(
          code: "invalid_credentials",
          message: "Passkey verification failed",
          status: :unauthorized
        )
      end

      def revoke_all
        current_user.revoke_all_devices!
        head :no_content
      end

      private

      def issue_bearer_token(user, platform: nil)
        payload = build_bearer_token_payload(user, platform: platform)
        render json: payload
      end

      # @lat: [[decoy-challenge-non-disclosure#How the web sign-in flow (Users::Webauthn::SessionsController) achieves the same non-disclosure]]
      def user_from_credential(credential)
        id = credential.is_a?(ActionController::Parameters) ? credential[:id] : credential.to_h[:id]
        return nil if id.blank?
        Passkey.find_by(external_id: id.to_s)&.user
      end
    end
  end
end
