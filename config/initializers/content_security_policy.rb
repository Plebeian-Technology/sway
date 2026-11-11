# frozen_string_literal: true

# @lat: [[local-error-reporting-design#Why CSP and Sentry initializers require SwayLocalErrorDsn directly]]
require_relative "../../lib/sway_local_error_dsn"

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self

    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
    policy.object_src :none

    policy.img_src :self, :data, :blob,
      "https://storage.googleapis.com",
      "https://*.googleapis.com",
      "https://*.gstatic.com",
      "https://*.cloudflare.com",
      "https://*.cloudflareinsights.com",
      "https://s3.amazonaws.com",
      "https://*.sway.vote",
      "https://sway.vote",
      "https://www.congress.gov",
      "https://bioguide.congress.gov",
      "https://*.house.gov",
      "https://*.senate.gov",
      "https://mgaleg.maryland.gov",
      "https://msa.maryland.gov",
      "https://www.baltimorecitycouncil.com",
      "https://www.baltimorecity.gov",
      "https://upload.wikimedia.org"

    # @lat: [[content-security-policy-directive-notes#Nonce generation and asset source allowances]]
    policy.font_src :self, :data, "https://fonts.gstatic.com"

    policy.script_src :self,
      "https://maps.googleapis.com",
      "https://static.cloudflareinsights.com",
      "https://challenges.cloudflare.com",
      "https://*.sway.vote",
      "https://sway.vote"

    policy.style_src :self, :unsafe_inline,
      "https://*.googleapis.com",
      "https://*.gstatic.com",
      "https://*.sway.vote",
      "https://sway.vote"

    policy.connect_src :self,
      "https://nominatim.openstreetmap.org",
      "https://maps.googleapis.com",
      "https://*.googleapis.com",
      # @lat: [[content-security-policy]]
      "https://*.ingest.sentry.io",
      "https://*.ingest.us.sentry.io",
      "https://cloudflareinsights.com",
      "https://*.cloudflareinsights.com",
      "https://challenges.cloudflare.com",
      "wss:",
      "https://*.sway.vote",
      "https://sway.vote"

    policy.frame_src :self,
      "https://challenges.cloudflare.com"

    policy.manifest_src :self
    policy.worker_src :self, :blob

    # @lat: [[content-security-policy-directive-notes#How the Vite dev server CSP source works]]
    if Rails.env.development?
      policy.script_src(*policy.script_src, :unsafe_eval, RailsVite.dev_server_csp_source)
      policy.style_src(*policy.style_src, :unsafe_inline)
      policy.connect_src(*policy.connect_src, RailsVite.dev_server_csp_source,
        RailsVite.dev_server_csp_source(websocket: true))
    end

    # @lat: [[content-security-policy-directive-notes#Why the local error collector origin is added to connect_src]]
    unless Rails.env.production?
      collector_origin = SwayLocalErrorDsn.browser_origin(ENV["VITE_RUSTRAK_DSN"])
      policy.connect_src(*policy.connect_src, collector_origin) if collector_origin
    end

    # @lat: [[content-security-policy-directive-notes#Nonce generation and asset source allowances]]
    policy.script_src(*policy.script_src, :blob) if Rails.env.test?

    policy.upgrade_insecure_requests if Rails.env.production?

    policy.report_uri "/csp-report"
  end

  config.content_security_policy_nonce_directives = %w[script-src]
  # @lat: [[content-security-policy-directive-notes#Nonce generation and asset source allowances]]
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }

  # @lat: [[content-security-policy-directive-notes#Why enforcement is switched by CSP_ENFORCE]]
  config.content_security_policy_report_only = ENV["CSP_ENFORCE"].blank?
end
