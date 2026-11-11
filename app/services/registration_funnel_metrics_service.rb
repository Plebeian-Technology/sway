# frozen_string_literal: true

# @lat: [[registration-funnel-telemetry#Registration funnel metrics and friction ranking]]
class RegistrationFunnelMetricsService
  STEPS = %w[
    landing
    phone_entered
    sms_verified
    passkey_enrolled
    address_submitted
    registration_completed
    first_vote_cast
  ].freeze

  STEP_LABELS = {
    "landing" => "Landing Page",
    "phone_entered" => "Phone Entered",
    "sms_verified" => "SMS Verified",
    "passkey_enrolled" => "Passkey Enrolled",
    "address_submitted" => "Address Submitted",
    "registration_completed" => "Registration Completed",
    "first_vote_cast" => "First Vote Cast"
  }.freeze

  TIME_RANGES = [
    {id: "24h", label: "Last 24 Hours"},
    {id: "7d", label: "Last 7 Days"},
    {id: "30d", label: "Last 30 Days"},
    {id: "all", label: "All Time"}
  ].freeze

  TRAFFIC_OPTIONS = [
    {id: "humans", label: "Humans"},
    {id: "bots", label: "Bots"},
    {id: "all", label: "All"}
  ].freeze

  Result = Struct.new(
    :time_range,
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
  )

  def initialize(time_range: "30d", attribution_key: nil, traffic: "humans")
    @time_range = (TIME_RANGES.any? { |r| r[:id] == time_range }) ? time_range : "30d"
    @attribution_key = attribution_key.presence
    @traffic = (TRAFFIC_OPTIONS.any? { |o| o[:id] == traffic }) ? traffic : "humans"
  end

  def call
    scope = base_scope

    step_counts = calculate_step_counts(scope)
    step_data = build_step_metrics(step_counts)
    landing_count = step_counts["landing"] || 0
    vote_count = step_counts["first_vote_cast"] || 0
    overall_conversion = landing_count.positive? ? ((vote_count.to_f / landing_count) * 100).round(1) : 0.0

    friction_points = build_friction_points(step_data)
    attributions = calculate_attribution_breakdown(scope)
    latency = calculate_latency_metrics(scope)

    Result.new(
      time_range: @time_range,
      filter_attribution_key: @attribution_key,
      steps: step_data,
      overall_conversion_rate: overall_conversion.to_f,
      friction_points: friction_points,
      attributions: attributions,
      latency: latency,
      time_ranges: TIME_RANGES,
      traffic: @traffic,
      traffic_options: TRAFFIC_OPTIONS,
      bot_visitor_count: window_scope.bots.distinct.count(:visitor_token)
    )
  end

  private

  def window_scope
    scope = apply_time_filter(RegistrationFunnelEvent.all)
    if @attribution_key.present?
      scope = if @attribution_key == "direct"
        scope.where("attribution_key IS NULL OR attribution_key = '' OR attribution_key = 'direct'")
      else
        scope.where(attribution_key: @attribution_key)
      end
    end
    scope
  end

  # @lat: [[registration-funnel-telemetry#Bot traffic classification#Traffic filter on the admin dashboard]]
  def base_scope
    case @traffic
    when "bots" then window_scope.bots
    when "all" then window_scope
    else window_scope.humans
    end
  end

  def apply_time_filter(scope)
    case @time_range
    when "24h"
      scope.where(created_at: 24.hours.ago..)
    when "7d"
      scope.where(created_at: 7.days.ago..)
    when "30d"
      scope.where(created_at: 30.days.ago..)
    when "all"
      scope
    else
      scope.where(created_at: 30.days.ago..)
    end
  end

  def calculate_step_counts(scope)
    raw = scope.group(:step).distinct.count(:visitor_token).transform_keys(&:to_s)
    counts = raw.dup
    counts["phone_entered"] = raw["phone_submitted"] if raw.key?("phone_submitted")
    counts["phone_submitted"] = raw["phone_entered"] if raw.key?("phone_entered")
    counts["registration_completed"] = raw["geocoding_completed"] if raw.key?("geocoding_completed")
    counts["geocoding_completed"] = raw["registration_completed"] if raw.key?("registration_completed")
    counts
  end

  def build_step_metrics(counts)
    landing_count = counts["landing"] || 0
    previous_count = nil

    STEPS.map.with_index do |step, index|
      count = counts[step] || 0
      label = STEP_LABELS.fetch(step, step.titleize)

      if index.zero?
        step_conversion_rate = 100.0
        drop_off_count = 0
        drop_off_rate = 0.0
        conversion_rate_from_start = landing_count.positive? ? 100.0 : 0.0
      else
        step_conversion_rate = previous_count.to_i.positive? ? ((count.to_f / previous_count.to_i) * 100).round(1) : 0.0
        drop_off_count = [previous_count.to_i - count, 0].max
        drop_off_rate = previous_count.to_i.positive? ? ((drop_off_count.to_f / previous_count.to_i) * 100).round(1) : 0.0
        conversion_rate_from_start = landing_count.positive? ? ((count.to_f / landing_count) * 100).round(1) : 0.0
      end

      previous_count = count

      {
        step: step,
        label: label,
        visitor_count: count,
        step_conversion_rate: step_conversion_rate,
        drop_off_count: drop_off_count,
        drop_off_rate: drop_off_rate,
        conversion_rate_from_start: conversion_rate_from_start
      }
    end
  end

  def build_friction_points(step_data)
    points = []
    (1...step_data.length).each do |i|
      prev = step_data[i - 1]
      curr = step_data[i]
      points << {
        from_step: prev[:step],
        to_step: curr[:step],
        label: "#{prev[:label]} → #{curr[:label]}",
        drop_off_count: curr[:drop_off_count],
        drop_off_rate: curr[:drop_off_rate]
      }
    end

    by_count = points.sort_by { |p| -p[:drop_off_count] }
    by_count.each_with_index { |p, idx| p[:rank_by_count] = idx + 1 }

    by_rate = points.sort_by { |p| -p[:drop_off_rate] }
    by_rate.each_with_index { |p, idx| p[:rank_by_rate] = idx + 1 }

    points.sort_by { |p| p[:rank_by_count] }
  end

  def calculate_attribution_breakdown(scope)
    landing_step = RegistrationFunnelEvent.steps[:landing]
    completed_step = RegistrationFunnelEvent.steps[:geocoding_completed]
    vote_step = RegistrationFunnelEvent.steps[:first_vote_cast]

    rows = scope
      .group("COALESCE(NULLIF(attribution_key, ''), 'direct')")
      .select(
        "COALESCE(NULLIF(attribution_key, ''), 'direct') AS source",
        "COUNT(DISTINCT CASE WHEN step = #{landing_step} THEN visitor_token END) AS visitors_count",
        "COUNT(DISTINCT CASE WHEN step = #{completed_step} THEN visitor_token END) AS registrations_count",
        "COUNT(DISTINCT CASE WHEN step = #{vote_step} THEN visitor_token END) AS votes_count"
      )

    rows.map do |row|
      visitors = row.visitors_count.to_i
      registrations = row.registrations_count.to_i
      votes = row.votes_count.to_i

      conversion_rate = visitors.positive? ? ((registrations.to_f / visitors) * 100).round(1) : 0.0
      vote_rate = visitors.positive? ? ((votes.to_f / visitors) * 100).round(1) : 0.0

      {
        source: row.source,
        visitors_count: visitors,
        registrations_count: registrations,
        votes_count: votes,
        conversion_rate: conversion_rate,
        vote_rate: vote_rate
      }
    end.sort_by { |a| -a[:visitors_count] }
  end

  def calculate_latency_metrics(scope)
    metadatas = scope
      .where(step: :geocoding_completed)
      .pluck(:metadata)

    latencies = metadatas.filter_map do |meta|
      lat = meta&.dig("latency_ms") || meta&.dig(:latency_ms)
      lat&.to_f
    end.sort

    return empty_latency if latencies.empty?

    count = latencies.size
    avg_s = (latencies.sum / count / 1000.0).round(2)
    min_s = (latencies.first / 1000.0).round(2)
    max_s = (latencies.last / 1000.0).round(2)

    mid = count / 2
    median_ms = count.odd? ? latencies[mid] : ((latencies[mid - 1] + latencies[mid]) / 2.0)
    median_s = (median_ms / 1000.0).round(2)

    p95_idx = [(count * 0.95).ceil - 1, 0].max
    p95_s = (latencies[p95_idx] / 1000.0).round(2)

    {
      sample_count: count,
      avg_seconds: avg_s,
      median_seconds: median_s,
      p95_seconds: p95_s,
      min_seconds: min_s,
      max_seconds: max_s
    }
  end

  def empty_latency
    {
      sample_count: 0,
      avg_seconds: 0.0,
      median_seconds: 0.0,
      p95_seconds: 0.0,
      min_seconds: 0.0,
      max_seconds: 0.0
    }
  end
end
