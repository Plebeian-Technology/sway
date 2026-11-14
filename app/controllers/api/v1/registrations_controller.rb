# frozen_string_literal: true

module Api
  module V1
    # @lat: [[passkey-only-sms-bootstrap#Api::V1::RegistrationsController: the two-step enrollment shape and token handling]]
    class RegistrationsController < BaseController
      include RelyingParty

      # @lat: [[phone-verification-rate-limits#Why Api::V1::RegistrationsController.create is rate-limited per IP]]
      rate_limit to: 5, within: 1.hour,
        by: -> { request.remote_ip },
        only: :create,
        if: -> { RateLimitConfig.enabled?(:sign_up) },
        with: -> { render_error(code: "rate_limited", message: "Too many registration attempts", status: :too_many_requests) },
        store: ApplicationController::RATE_LIMIT_STORE

      def public_endpoint?
        %w[create callback].include?(action_name)
      end

      # @lat: [[passkey-only-sms-bootstrap#Api::V1::RegistrationsController: the two-step enrollment shape and token handling]]
      def create
        p = params.require(:registration).permit(:sms_verified_token, :phone)
        token = p[:sms_verified_token].to_s
        phone = p[:phone].to_s.normalize_phone

        stored_sms = SmsVerificationToken.peek(token)
        unless stored_sms
          return render_error(
            code: "invalid_sms_token",
            message: "SMS verification token invalid or expired",
            status: :unauthorized
          )
        end
        unless stored_sms[:phone].to_s == PhoneCacheKey.digest(phone)
          return render_error(
            code: "invalid_sms_token",
            message: "Phone mismatch",
            status: :unauthorized
          )
        end

        # @lat: [[passkey-only-sms-bootstrap#Api::V1::RegistrationsController: the two-step enrollment shape and token handling]]
        existing_user = User.find_by(phone: phone)
        if existing_user&.has_sway_passkey?
          return render_error(
            code: "phone_already_registered",
            message: "This phone already has a Sway account. Sign in with your passkey, or contact Sway support if you've lost access.",
            status: :conflict
          )
        end

        webauthn_id = existing_user&.webauthn_id.presence || WebAuthn.generate_user_id
        create_options = relying_party.options_for_registration(
          user: {id: webauthn_id, name: phone, display_name: phone},
          # @lat: [[discoverable-passkey-design#Why registration asks for resident_key: "preferred"]]
          authenticator_selection: {resident_key: "preferred", user_verification: "required"},
          exclude: []
        )
        challenge_id = SecureRandom.hex(16)
        Rails.cache.write(
          "webauthn:challenge:#{challenge_id}",
          {
            challenge: create_options.challenge,
            phone: phone,
            sms_verified_token: token,
            webauthn_id: webauthn_id
          },
          expires_in: 5.minutes
        )

        # @lat: [[webauthn-camelcase-response-shape#Why mobile WebAuthn responses keep the spec's camelCase shape]]
        render json: create_options.as_json.merge(challenge_id: challenge_id)
      end

      def callback
        permit_credential = {} #: Hash[Symbol, untyped]
        p = params.require(:registration).permit(:challenge_id, :platform, credential: permit_credential)
        cache_key = "webauthn:challenge:#{p[:challenge_id]}"
        cached = Rails.cache.read(cache_key)
        unless cached
          return render_error(
            code: "invalid_challenge",
            message: "Challenge expired or missing",
            status: :unauthorized
          )
        end

        log_passkey_client_origin(p[:credential])

        webauthn_credential = relying_party.verify_registration(
          credential_for_verify(p[:credential]),
          cached[:challenge],
          user_verification: true
        )

        result = nil #: Hash[Symbol, untyped]?
        already_registered = false
        invalid_sms_token = false
        User.transaction do
          Rails.cache.delete(cache_key)
          # @lat: [[passkey-only-sms-bootstrap#Api::V1::RegistrationsController: the two-step enrollment shape and token handling]]
          stored_sms = SmsVerificationToken.peek(cached[:sms_verified_token])
          unless stored_sms && stored_sms[:phone].to_s == PhoneCacheKey.digest(cached[:phone])
            invalid_sms_token = true
            raise ActiveRecord::Rollback
          end

          existing = User.find_by(phone: cached[:phone])
          if existing&.has_sway_passkey?
            already_registered = true
            raise ActiveRecord::Rollback
          end

          user = existing || User.create!(
            phone: cached[:phone],
            is_phone_verified: true,
            webauthn_id: cached[:webauthn_id].presence
          )
          user.update!(is_phone_verified: true) if existing && !existing.is_phone_verified

          passkey = Passkey.new(
            user: user,
            external_id: webauthn_credential.id,
            label: p[:platform].presence || "Mobile",
            public_key: webauthn_credential.public_key,
            sign_count: webauthn_credential.sign_count,
            # @lat: [[passkey-aaguid-registry#What an AAGUID is]]
            aaguid: webauthn_credential.try(:aaguid)
          )
          passkey.validate!
          passkey.save!
          NotificationPreference.seed_defaults_for(user)

          result = build_bearer_token_payload(user, platform: p[:platform])

          # @lat: [[sms-verification-token-design#Why the token is spent last]]
          unless SmsVerificationToken.consume!(cached[:sms_verified_token], phone: cached[:phone])
            invalid_sms_token = true
            raise ActiveRecord::Rollback
          end
        end

        if invalid_sms_token
          return render_error(
            code: "invalid_sms_token",
            message: "SMS verification token invalid or expired",
            status: :unauthorized
          )
        end

        if already_registered
          return render_error(
            code: "phone_already_registered",
            message: "This phone already has a Sway account. Sign in with your passkey, or contact Sway support if you've lost access.",
            status: :conflict
          )
        end

        render json: result
      rescue ActiveRecord::RecordInvalid => e
        return render_phone_already_registered if phone_taken?(e)

        render_error(
          code: "invalid_passkey",
          message: e.record.errors.full_messages.to_sentence,
          status: :unprocessable_content
        )
      rescue ActiveRecord::RecordNotUnique => e
        raise unless phone_taken?(e)

        render_phone_already_registered
      rescue WebAuthn::Error
        Rails.cache.delete(cache_key) if cache_key
        render_error(
          code: "invalid_credentials",
          message: "Passkey registration failed",
          status: :unauthorized
        )
      end

      private

      # @lat: [[identity-and-access#Identity and access#The phone number is the account#First-passkey enrollment]]
      def phone_taken?(error)
        case error
        when ActiveRecord::RecordInvalid
          error.record.is_a?(User) && error.record.errors.of_kind?(:phone, :taken)
        when ActiveRecord::RecordNotUnique
          error.message.include?("users.phone")
        else
          false
        end
      end

      def render_phone_already_registered
        render_error(
          code: "phone_already_registered",
          message: "This phone already has a Sway account. Sign in with your passkey, or contact Sway support if you've lost access.",
          status: :conflict
        )
      end
    end
  end
end
