# frozen_string_literal: true

Rails.application.config.fcm = ActiveSupport::OrderedOptions.new.tap do |c|
  # @lat: [[pre-autoload-credential-trimming#FCM (config/initializers/fcm.rb)]]
  project_id = ENV["FCM_PROJECT_ID"].to_s.strip.presence
  # @lat: [[settings-and-secrets#Push notification credentials]]
  c.project_id = project_id unless project_id&.match?(/[<>]/)
  c.service_account_json = EnvSecret.read_base64("FCM_SERVICE_ACCOUNT_JSON")
  c.enabled = c.project_id.present? && c.service_account_json.present?
end
