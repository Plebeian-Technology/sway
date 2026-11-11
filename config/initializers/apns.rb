# frozen_string_literal: true

Rails.application.config.apns = ActiveSupport::OrderedOptions.new.tap do |c|
  c.team_id = Sway::Settings.mobile.apple_team_id
  c.bundle_id = Sway::Settings.mobile.apple_bundle_id
  c.env = ENV["APNS_ENV"].to_s.strip.presence || (Rails.env.production? ? "production" : "development")

  # @lat: [[pre-autoload-credential-trimming#APNs (config/initializers/apns.rb)]]
  # @lat: [[apns-key-environment-pairing#Why the key pair is chosen by APNS_ENV]]
  production_auth_key_p8 = EnvSecret.read_base64("APNS_AUTH_KEY_P8")
  production_key_id = ENV["APNS_KEY_ID"].to_s.strip.presence
  sandbox_auth_key_p8 = EnvSecret.read_base64("APNS_SANDBOX_AUTH_KEY_P8")
  sandbox_key_id = ENV["APNS_SANDBOX_KEY_ID"].to_s.strip.presence

  if c.env == "production"
    c.auth_key_p8 = production_auth_key_p8
    c.key_id = production_key_id
  else
    c.auth_key_p8 = sandbox_auth_key_p8
    c.key_id = sandbox_key_id
  end

  c.enabled = c.auth_key_p8.present? && c.key_id.present? && c.team_id.present? && c.bundle_id.present?
end
