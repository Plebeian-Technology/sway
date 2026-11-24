# frozen_string_literal: true

module Users
  # @lat: [[passkey-management-page-overview#Threats considered]]
  class PasskeysController < ApplicationController
    include Authentication

    # @lat: [[discoverable-passkey-design#Why an already-signed-in user still needs a fresh SMS token to add a passkey]]
    ADD_PASSKEY_VERIFY_WINDOW = 10.minutes
    ADD_PASSKEY_FAILED_MESSAGE = "We couldn't add this passkey. Try again."
    DEFAULT_PASSKEY_LABELS = ["Passkey", "New passkey"].freeze
    REMOVE_PASSKEY_CONFIRM_FIRST_MESSAGE = "Confirm your phone number first."
    LAST_PASSKEY_MESSAGE = "Your last passkey cannot be removed."

    rate_limit to: 10, within: 1.hour,
      name: "verify_phone_ip",
      by: -> { request.remote_ip },
      only: :verify_phone,
      if: -> { RateLimitConfig.enabled?(:phone_verify) },
      with: -> { render_rate_limited(retry_after: 1.hour.to_i) },
      store: ApplicationController::RATE_LIMIT_STORE
    rate_limit to: 3, within: 1.hour,
      name: "verify_phone_phone",
      # @lat: [[phone-cache-hashing]]
      by: -> { "#{PhoneCacheKey.digest(current_user&.phone)}:#{request.remote_ip}" },
      only: :verify_phone,
      if: -> { RateLimitConfig.enabled?(:phone_verify) },
      with: -> { render_rate_limited(retry_after: 1.hour.to_i) },
      store: ApplicationController::RATE_LIMIT_STORE
    rate_limit to: 10, within: 1.hour,
      name: "confirm_phone_ip",
      by: -> { request.remote_ip },
      only: :confirm_phone,
      if: -> { RateLimitConfig.enabled?(:phone_verify) },
      with: -> { render_rate_limited(retry_after: 1.hour.to_i) },
      store: ApplicationController::RATE_LIMIT_STORE
    rate_limit to: 5, within: 1.hour,
      name: "confirm_phone_phone",
      # @lat: [[phone-cache-hashing]]
      by: -> { PhoneCacheKey.digest(current_user&.phone) },
      only: :confirm_phone,
      if: -> { RateLimitConfig.enabled?(:phone_verify) },
      with: -> { render_rate_limited(retry_after: 1.hour.to_i) },
      store: ApplicationController::RATE_LIMIT_STORE

    def index
      passkeys = current_user.passkeys.order(created_at: :desc).map do |p|
        {
          id: p.id,
          label: p.label,
          created_at: p.created_at.iso8601,
          last_used_at: p.last_used_at&.iso8601,
          # @lat: [[passkey-aaguid-registry#Why some saved passkeys can never resolve to a name]]
          device: p.device_name
        }
      end

      render_inertia_or_json(
        page: Pages::PASSKEY_MANAGEMENT,
        props: {passkeys: passkeys}
      )
    end

    def verify_phone
      SwayLogging.info(
        "passkeys.add.verify_phone_requested",
        user_id: current_user.id,
        phone_last4: current_user.phone.to_s.last(4)
      )
      wait = phone_verification_send_wait(current_user.phone)
      return render_rate_limited(retry_after: wait) if wait

      render_phone_verification_send(session, current_user.phone)
    end

    def confirm_phone
      approved =
        Sway::Settings.dev_login.skip_phone_verification ||
        add_passkey_code_approved?

      session[:add_passkey_verified_at] = Time.current.to_i if approved
      render json: {success: approved}, status: :ok
    end

    def add_options
      return render json: {success: false, message: "Confirm your phone number first."}, status: :ok unless add_passkey_verified?

      create_options =
        relying_party.options_for_registration(
          user: {name: current_user.phone, id: current_user.webauthn_id},
          authenticator_selection: {
            # @lat: [[discoverable-passkey-design#Why registration asks for resident_key: "preferred"]]
            resident_key: "preferred",
            user_verification: "required"
          },
          exclude: current_user.passkeys.pluck(:external_id)
        )

      session[:add_passkey_registration] = {challenge: create_options.challenge}
      render json: create_options
    end

    def add_callback
      challenge =
        session.dig(:add_passkey_registration, "challenge") ||
        session.dig(:add_passkey_registration, :challenge)

      unless add_passkey_verified? && challenge.present?
        return render json: {success: false, message: "Add-a-passkey session expired. Please try again."}, status: :ok
      end

      # @lat: [[add-passkey-nested-credential-bug#Why add_callback reads the credential from publicKeyCredential]]
      webauthn_passkey =
        relying_party.verify_registration(
          params.require(:publicKeyCredential),
          challenge,
          user_verification: true
        )

      passkey =
        current_user.passkeys.build(
          external_id: webauthn_passkey.id,
          label: disambiguate_passkey_label(params[:passkey_label]),
          public_key: webauthn_passkey.public_key,
          sign_count: webauthn_passkey.sign_count,
          aaguid: webauthn_passkey.try(:aaguid)
        )

      if passkey.save
        SwayLogging.info(
          "passkeys.add.completed",
          user_id: current_user.id,
          passkey_id: passkey.id
        )
        clear_add_passkey_session
        render json: {success: true}
      else
        render json: {success: false, message: passkey.errors.full_messages.to_sentence}, status: :ok
      end
    rescue WebAuthn::Error => e
      SwayLogging.log_exception(
        "passkeys.add.verification_failed",
        exception: e,
        level: :warn,
        user_id: current_user.id
      )
      Sentry.capture_message(
        "passkeys.add.verification_failed",
        level: :warning,
        tags: {exception_class: e.class.name},
        fingerprint: ["passkeys.add.verification_failed", e.class.name],
        extra: {exception_class: e.class.name}
      )
      render json: {success: false, message: ADD_PASSKEY_FAILED_MESSAGE}, status: :ok
    ensure
      session.delete(:add_passkey_registration)
    end

    # @lat: [[passkey-management-page-overview#Removing a passkey]]
    def destroy
      passkey = current_user.passkeys.find(params[:id])

      unless add_passkey_verified?
        return render json: {success: false, message: REMOVE_PASSKEY_CONFIRM_FIRST_MESSAGE}, status: :ok
      end

      removed = Passkey.transaction do
        next false if current_user.passkeys.count <= User::MIN_PASSKEY_COUNT

        passkey.destroy!
      end
      return render json: {success: false, message: LAST_PASSKEY_MESSAGE}, status: :ok unless removed

      SwayLogging.info("passkeys.remove.completed", user_id: current_user.id, passkey_id: passkey.id)
      clear_add_passkey_session
      render json: {success: true}
    end

    private

    def disambiguate_passkey_label(raw_label)
      base_label = raw_label.to_s.strip.presence || "New passkey"
      return base_label unless raw_label.blank? || DEFAULT_PASSKEY_LABELS.include?(base_label)

      existing_labels = current_user.passkeys.pluck(:label)
      return base_label unless existing_labels.include?(base_label)

      suffix = 2
      suffix += 1 while existing_labels.include?("#{base_label} #{suffix}")
      "#{base_label} #{suffix}"
    end

    def add_passkey_verified?
      verified_at = session[:add_passkey_verified_at]
      verified_at.present? && Time.zone.at(verified_at.to_i) > ADD_PASSKEY_VERIFY_WINDOW.ago
    end

    def clear_add_passkey_session
      session.delete(:add_passkey_verified_at)
      session.delete(:add_passkey_registration)
    end

    def add_passkey_code_approved?
      verification_approved?(to: "+1#{current_user.phone}", code: params[:code])
    rescue Twilio::REST::RestError => e
      # @lat: [[twilio-error-phone-redaction#Why VotingReminderJob's inner rescue logs only structured fields and the error class]]
      SwayLogging.warn(
        "passkeys.add.confirm_failed",
        user_id: current_user.id,
        twilio_code: e.code
      )
      false
    rescue Twilio::REST::TwilioError => e
      # @lat: [[twilio-error-phone-redaction#Why a Twilio network failure is answered, not raised]]
      SwayLogging.warn(
        "passkeys.add.confirm_failed",
        user_id: current_user.id,
        error_class: e.class.name
      )
      false
    end
  end
end
