# frozen_string_literal: true

module RelyingParty
  extend ActiveSupport::Concern

  included do
    def relying_party
      # @lat: [[webauthn-rp-id-settings-resolution#Why RelyingParty.relying_party logs the resolved values on every call]]
      resolved_id = resolved_rp_id

      resolved_origins = origins

      # @lat: [[webauthn-rp-id-settings-resolution#Why RelyingParty.relying_party logs the resolved values on every call]]
      SwayLogging.info(
        "webauthn.relying_party " \
        "rp_id=#{resolved_id || "(derived from origin)"} " \
        "rp_id_source=#{rp_id_source(resolved_id)} " \
        "origins=#{resolved_origins.inspect} " \
        "request_host=#{request.host_with_port} " \
        "request_protocol=#{request.protocol}"
      )

      WebAuthn::RelyingParty.new(
        allowed_origins: resolved_origins,
        # @lat: [[webauthn-rp-id-settings-resolution#Why the relying party name has no preview/staging suffix]]
        name: "sway-#{Rails.env}",
        credential_options_timeout: 120_000,
        id: resolved_id
      )
    end

    private

    # @lat: [[webauthn-settings-consolidation#Why rp_id has no default]]
    def resolved_rp_id
      setting = Sway::Settings.webauthn.rp_id
      if Rails.env.production?
        setting || raise(Sway::Settings::MissingValues, "WEBAUTHN_RP_ID is not set")
      elsif setting == "localhost" && request.host.present? && request.host != "localhost" && request.host != "test.host"
        request.host
      else
        setting || request.host
      end
    end

    def rp_id_source(resolved_id)
      # @lat: [[webauthn-rp-id-settings-resolution#Why rp_id_source re-derives the source instead of re-reading the raw setting]]
      return "env" if Sway::Settings.webauthn.rp_id.present? && resolved_id == Sway::Settings.webauthn.rp_id
      "derived_from_origin"
    end

    def origins
      base_origins = if Sway::Settings.webauthn.allowed_origins.present?
        Sway::Settings.webauthn.allowed_origins
      elsif Rails.env.production?
        # @lat: [[webauthn-settings-consolidation#Why production names its origins and domain in the deploy file]]
        raise Sway::Settings::MissingValues, "WEBAUTHN_ALLOWED_ORIGINS is not set"
      else
        ["#{request.protocol}#{request.host_with_port}"]
      end

      (base_origins + android_origins).uniq
    end

    def android_origins
      Sway::Settings.mobile.android_cert_sha256_fingerprints.filter_map do |fp|
        hex = fp.to_s.delete(":")
        next if hex.blank?

        hash = Base64.urlsafe_encode64([hex].pack("H*"), padding: false)
        "android:apk-key-hash:#{hash}"
      end
    end
  end
end
