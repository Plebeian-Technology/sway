# frozen_string_literal: true

module Users
  module Webauthn
    class RegistrationController < ApplicationController
      include VerifiedPhoneSession
      include OnboardingSafetyNet

      class AlreadyRegistered < StandardError; end

      ALREADY_REGISTERED_MESSAGE = "This phone already has a Sway account. Sign in with your passkey, or contact Sway support if you've lost access."
      SIGN_IN_FAILED_MESSAGE = "Your passkey was saved, but Sway couldn't sign you in. Sign in with your passkey to continue."

      # @lat: [[phone-verification-rate-limits#Why Api::V1::RegistrationsController.create is rate-limited per IP]]
      rate_limit to: 20, within: 1.hour,
        name: "create",
        # @lat: [[phone-cache-hashing]]
        by: -> {
          # @type self: Users::Webauthn::RegistrationController
          verified_phone = session[:verified_phone]
          verified_phone.present? ? PhoneCacheKey.digest(verified_phone) : request.remote_ip
        },
        only: :create,
        if: -> { RateLimitConfig.enabled?(:sign_up) },
        with: -> { render_rate_limited(retry_after: 1.hour.to_i) },
        store: ApplicationController::RATE_LIMIT_STORE

      skip_before_action :authenticate_sway_user!

      # @lat: [[identity-and-access#Identity and access#The phone number is the account#First-passkey enrollment]]
      def create
        session.delete(:current_registration)
        user = User.find_or_initialize_by(phone: session[:verified_phone])
        verified_phone_last4 = session[:verified_phone].to_s.last(4)

        user.is_phone_verified = verified_phone_current?(session[:phone])

        if user.is_phone_verified
          if user.has_sway_passkey?
            return render json: {errors: [ALREADY_REGISTERED_MESSAGE]}, status: :conflict
          end

          create_options =
            relying_party.options_for_registration(
              user: {
                name: session[:verified_phone],
                id: user.webauthn_id
              },
              authenticator_selection: {
                # @lat: [[identity-and-access#Identity and access#The phone number is the account#Enrollment credential metadata]]
                resident_key: "preferred",
                user_verification: "required"
              },
              exclude: user.passkeys.pluck(:external_id)
            )

          if user.valid?
            session[:current_registration] = {
              challenge: create_options.challenge,
              user_attributes: sanitized_user_attributes(user.attributes, session[:verified_phone]).stringify_keys
            }

            SwayLogging.info(
              "webauthn.registration.create_challenge",
              user_id: user.id,
              phone_last4: verified_phone_last4,
              passkey_count: user.passkeys.count
            )
            render json: create_options
          else
            SwayLogging.warn(
              "webauthn.registration.invalid_user",
              user_id: user.id,
              phone_last4: verified_phone_last4,
              errors: user.errors.full_messages
            )
            render json: {
                     errors: user.errors.full_messages
                   },
              status: :unprocessable_content
          end
        else
          render json: {
                   success: false,
                   message: "Please confirm your phone number first."
                 },
            status: :ok
        end
      end

      # @lat: [[identity-and-access#Identity and access#The phone number is the account#First-passkey enrollment]]
      def callback
        user = nil #: User?
        current_registration = session[:current_registration]
        registration_challenge =
          current_registration&.dig("challenge") ||
          current_registration&.dig(:challenge)
        attributes =
          current_registration&.dig("user_attributes") ||
          current_registration&.dig(:user_attributes)
        verified_phone = session[:verified_phone]

        if registration_challenge.blank? || !verified_phone_current?(verified_phone)
          SwayLogging.warn("webauthn.registration.challenge_missing")
          redirect_to root_path, alert: "Registration session expired. Please try again."
          return
        end

        webauthn_passkey =
          relying_party.verify_registration(
            params,
            registration_challenge,
            user_verification: true
          )

        passkey =
          Passkey.new(
            external_id: webauthn_passkey.id,
            label: params[:passkey_label],
            public_key: webauthn_passkey.public_key,
            sign_count: webauthn_passkey.sign_count,
            # @lat: [[identity-and-access#Identity and access#The phone number is the account#Enrollment credential metadata]]
            aaguid: webauthn_passkey.try(:aaguid)
          )

        passkey_saved = false
        User.transaction do
          account = User.find_or_initialize_by(phone: verified_phone)
          user = account
          raise AlreadyRegistered if account.has_sway_passkey?

          attrs = sanitized_user_attributes(attributes, verified_phone)
          attrs.delete(:webauthn_id) if account.persisted? && account.webauthn_id.present?
          account.assign_attributes(attrs)
          account.save!
          passkey.user = account
          passkey_saved = passkey.save
          raise ActiveRecord::Rollback unless passkey_saved
        end

        if passkey_saved && user
          begin
            sign_in(user)
          rescue => e
            SwayLogging.log_exception(
              "webauthn.registration.sign_in_failed",
              exception: e,
              user_id: user.id,
              passkey_id: passkey.id,
              phone_last4: verified_phone.to_s.last(4)
            )
            Sentry.capture_exception(e, extra: {user_id: user.id, passkey_id: passkey.id})
            redirect_to root_path, alert: SIGN_IN_FAILED_MESSAGE
            return
          end
          SwayLogging.info(
            "webauthn.registration.completed",
            user_id: user.id,
            passkey_id: passkey.id,
            phone_last4: verified_phone.to_s.last(4)
          )

          redirect_to sway_registration_index_path
        else
          SwayLogging.warn(
            "webauthn.registration.passkey_save_failed",
            user_id: user&.id,
            phone_last4: verified_phone.to_s.last(4),
            errors: passkey.errors.full_messages
          )
          redirect_to root_path, alert: "Couldn't register your Passkey"
        end
      rescue AlreadyRegistered
        redirect_to root_path, alert: ALREADY_REGISTERED_MESSAGE
      rescue WebAuthn::Error => e
        SwayLogging.log_exception(
          "webauthn.registration.verification_failed",
          exception: e,
          level: :warn,
          user_id: user&.id,
          phone_last4: verified_phone.to_s.last(4)
        )
        redirect_to root_path, alert: "Verification failed: #{e.message}"
      rescue ActiveRecord::RecordInvalid => e
        return redirect_to(root_path, alert: ALREADY_REGISTERED_MESSAGE) if phone_taken?(e)

        SwayLogging.log_exception(
          "webauthn.registration.record_invalid",
          exception: e,
          level: :warn,
          user_id: user&.id,
          phone_last4: verified_phone.to_s.last(4),
          errors: e.record.errors.full_messages
        )
        redirect_to root_path, alert: "Registration failed: #{e.record.errors.full_messages.join(", ")}"
      rescue ActiveRecord::RecordNotUnique => e
        return redirect_to(root_path, alert: ALREADY_REGISTERED_MESSAGE) if phone_taken?(e)

        SwayLogging.log_exception(
          "webauthn.registration.passkey_save_failed",
          exception: e,
          level: :warn,
          user_id: user&.id,
          phone_last4: verified_phone.to_s.last(4)
        )
        redirect_to root_path, alert: "Couldn't register your Passkey"
      ensure
        session.delete(:current_registration)
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

      def sanitized_user_attributes(attributes, verified_phone)
        empty_attributes = {}
        # @type var empty_attributes: Hash[untyped, untyped]
        raw_attributes = attributes.is_a?(Hash) ? attributes : empty_attributes

        {
          phone: verified_phone,
          webauthn_id: read_attribute(raw_attributes, "webauthn_id"),
          email: read_attribute(raw_attributes, "email"),
          full_name: read_attribute(raw_attributes, "full_name"),
          is_phone_verified:
            read_attribute(raw_attributes, "is_phone_verified"),
          # @lat: [[identity-and-access#Identity and access#The phone number is the account#Enrollment attributes exclude admin privileges]]
          is_email_verified:
            read_attribute(raw_attributes, "is_email_verified"),
          is_registered_to_vote:
            read_attribute(raw_attributes, "is_registered_to_vote")
        }.compact
      end

      def read_attribute(attributes, key)
        return attributes[key] if attributes.key?(key)

        attributes[key.to_sym]
      end
    end
  end
end
