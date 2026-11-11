Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.custom_options =
    lambda do |event|
      payload = event.payload

      {
        request_id: payload[:request_id],
        user_id: payload[:user_id],
        sway_locale_id: payload[:sway_locale_id],
        remote_ip: payload[:remote_ip],
        user_agent: payload[:user_agent],
        api_request: payload[:api_request],
        inertia: payload[:inertia],
        inertia_partial_component: payload[:inertia_partial_component],
        sql_queries_count: payload[:sql_queries_count],
        sql_cached_queries_count: payload[:sql_cached_queries_count],
        sql_max_fingerprint_repeats: payload[:sql_max_fingerprint_repeats],
        exception_class: payload[:exception]&.first,
        exception_message: if payload[:exception]&.last
                             SwayLogging.redact_anthropic_key(
                               SwayErrorScrubber.scrub_text(payload[:exception]&.last.to_s)
                             )
                           end
      }.compact
    end

  config.lograge.ignore_actions = %w[
    Rails::HealthController#show
    HealthController#show
    ::HealthController#show
    HealthController
    ::HealthController
    Rails::HealthController
  ]
end
