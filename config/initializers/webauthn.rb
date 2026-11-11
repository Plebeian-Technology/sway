webauthn_settings = Sway::Settings.webauthn

# @lat: [[webauthn-settings-consolidation#Why production names its origins and domain in the deploy file]]
if Rails.env.production? && !Anyway::Settings.suppress_required_validations
  missing = []
  missing << "WEBAUTHN_ALLOWED_ORIGINS" if webauthn_settings.allowed_origins.empty?
  missing << "WEBAUTHN_RP_ID" if webauthn_settings.rp_id.nil?

  if missing.any?
    raise Sway::Settings::MissingValues,
      "Passkeys cannot work in production without #{missing.join(" and ")}. " \
      "Set them in config/deploy.yml under env.clear."
  end
end

WebAuthn.configure do |config|
  # @lat: [[webauthn-settings-consolidation#Why allowed_origins and rp_id share one prefix]]
  config.allowed_origins =
    webauthn_settings.allowed_origins.presence ||
    (
      if Rails.env.production?
        []
      else
        %w[
          https://localhost:3333
          http://localhost:3333
          https://localhost:3000
          http://localhost:3000
        ]
      end
    )

  config.rp_name = "Sway"

  # @lat: [[webauthn-rp-id-settings-resolution#Why rp_id_source re-derives the source instead of re-reading the raw setting]]
  config.rp_id = webauthn_settings.rp_id
end
