# frozen_string_literal: true

module Api
  module V1
    # @lat: [[discoverable-passkey-design#Why an already-signed-in user still needs a fresh SMS token to add a passkey]]
    class PasskeysController < BaseController
      include RelyingParty

      DEFAULT_PASSKEY_LABELS = ["Passkey", "New passkey"].freeze

      def create
        p = params.require(:passkey).permit(:sms_verified_token, :label)
        stored = SmsVerificationToken.peek(p[:sms_verified_token])
        unless stored && stored[:phone].to_s == PhoneCacheKey.digest(current_user.phone)
          return render_error(
            code: "invalid_sms_token",
            message: "Confirm your phone number first.",
            status: :unauthorized
          )
        end

        create_options = relying_party.options_for_registration(
          user: {id: current_user.webauthn_id, name: current_user.phone, display_name: current_user.phone},
          # @lat: [[discoverable-passkey-design#Why registration asks for resident_key: "preferred"]]
          authenticator_selection: {resident_key: "preferred", user_verification: "required"},
          exclude: current_user.passkeys.pluck(:external_id)
        )
        challenge_id = SecureRandom.hex(16)
        Rails.cache.write(
          "webauthn:challenge:#{challenge_id}",
          {
            challenge: create_options.challenge,
            user_id: current_user.id,
            phone: current_user.phone,
            sms_verified_token: p[:sms_verified_token],
            label: p[:label]
          },
          expires_in: 5.minutes
        )
        render json: create_options.as_json.merge(challenge_id: challenge_id)
      end

      def callback
        permit_credential = {} #: Hash[Symbol, untyped]
        p = params.require(:passkey).permit(:challenge_id, :label, credential: permit_credential)
        cache_key = "webauthn:challenge:#{p[:challenge_id]}"
        cached = Rails.cache.read(cache_key)
        # @lat: [[discoverable-passkey-design#Why the cached challenge is bound to the authenticated caller]]
        unless cached && cached[:user_id] == current_user.id
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

        invalid_sms_token = false
        passkey = nil #: Passkey?
        User.transaction do
          Rails.cache.delete(cache_key)
          stored_sms = SmsVerificationToken.peek(cached[:sms_verified_token])
          unless stored_sms && stored_sms[:phone].to_s == PhoneCacheKey.digest(cached[:phone])
            invalid_sms_token = true
            raise ActiveRecord::Rollback
          end

          candidate = current_user.passkeys.build(
            external_id: webauthn_credential.id,
            label: disambiguate_passkey_label(current_user, cached[:label].presence || p[:label].presence),
            public_key: webauthn_credential.public_key,
            sign_count: webauthn_credential.sign_count,
            # @lat: [[passkey-aaguid-registry#Why some saved passkeys can never resolve to a name]]
            aaguid: webauthn_credential.try(:aaguid)
          )
          candidate.validate!

          unless SmsVerificationToken.consume!(cached[:sms_verified_token], phone: cached[:phone])
            invalid_sms_token = true
            raise ActiveRecord::Rollback
          end

          candidate.save!
          passkey = candidate
        end

        if invalid_sms_token || passkey.nil?
          return render_error(
            code: "invalid_sms_token",
            message: "SMS verification token invalid or expired",
            status: :unauthorized
          )
        end

        render json: {id: passkey.id, label: passkey.label}
      rescue ActiveRecord::RecordInvalid => e
        render_error(
          code: "invalid_passkey",
          message: e.record.errors.full_messages.to_sentence,
          status: :unprocessable_content
        )
      rescue WebAuthn::Error
        Rails.cache.delete(cache_key) if cache_key
        render_error(
          code: "invalid_credentials",
          message: "Passkey verification failed",
          status: :unauthorized
        )
      end

      private

      def disambiguate_passkey_label(user, raw_label)
        base_label = raw_label.to_s.strip.presence || "New passkey"
        return base_label unless raw_label.blank? || DEFAULT_PASSKEY_LABELS.include?(base_label)

        existing_labels = user.passkeys.pluck(:label)
        return base_label unless existing_labels.include?(base_label)

        suffix = 2
        suffix += 1 while existing_labels.include?("#{base_label} #{suffix}")
        "#{base_label} #{suffix}"
      end
    end
  end
end
