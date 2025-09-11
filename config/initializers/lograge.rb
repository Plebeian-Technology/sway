Rails.application.configure do
  config.lograge.enabled = true

  config.lograge.ignore_actions = %w[
    Rails::HealthController#show
    HealthController#show
    ::HealthController#show
    HealthController
    ::HealthController
    Rails::HealthController
  ]
end
