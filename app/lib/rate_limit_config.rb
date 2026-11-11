# frozen_string_literal: true

module RateLimitConfig
  # @lat: [[rate-limit-kill-switches#Why the preferences scope is rate-limited by IP]]
  FLAG_FOR = {
    sign_in: :sign_in_enabled,
    sign_up: :sign_up_enabled,
    phone_verify: :phone_verify_enabled,
    email_verify: :email_verify_enabled,
    legislator_email: :legislator_email_enabled,
    csp_report: :csp_report_enabled,
    org_invite: :org_invite_enabled,
    device_push_token: :device_push_token_enabled,
    bootstrap: :bootstrap_enabled,
    # @lat: [[rate-limit-kill-switches#Why the preferences scope is rate-limited by IP]]
    preferences: :preferences_enabled,
    bill_summary_report: :bill_summary_report_enabled
  }.freeze

  # @lat: [[rate-limit-kill-switches#Why the preferences scope is rate-limited by IP]]
  def self.enabled?(scope)
    attribute = FLAG_FOR.fetch(scope)
    return false unless Rails.env.production?

    Sway::Settings.rate_limits.public_send(attribute)
  end
end
