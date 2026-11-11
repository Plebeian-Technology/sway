# frozen_string_literal: true

# @lat: [[registration-funnel-telemetry#Registration funnel serialization]]
class RegistrationFunnelResource < ApplicationResource
  attributes :time_range,
    :filter_attribution_key,
    :steps,
    :overall_conversion_rate,
    :friction_points,
    :attributions,
    :latency,
    :time_ranges,
    :traffic,
    :traffic_options,
    :bot_visitor_count
end
