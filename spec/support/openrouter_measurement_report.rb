# frozen_string_literal: true

require "fileutils"
require "json"

module OpenRouterMeasurementReport
  USAGE_FIELDS = %w[
    cached_tokens
    cache_read_input_tokens
    cache_creation_input_tokens
    completion_tokens
    input_tokens
    output_tokens
    prompt_tokens
    total_tokens
  ].freeze

  module_function

  # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes#Prompt caching measurement on the pinned OpenRouter route]]
  def build(recorded_at:)
    {
      "recorded_at" => recorded_at.utc.iso8601,
      "date" => recorded_at.utc.to_date.iso8601,
      "sway_prompt_cache_reached" => false,
      "choices" => []
    }
  end

  def choice(label:, model:)
    {
      "requested_alias" => label,
      "requested_model_id" => model,
      "schema_measurements" => {},
      "cache_measurement" => {
        "sway_prompt_cache_reached" => false,
        "calls" => [],
        "cache_threshold_tokens" => nil,
        "cache_threshold_status" => "not_established"
      }
    }
  end

  def usage_snapshot(usage)
    return {} unless usage.is_a?(Hash)

    snapshot = usage.each_with_object({}) do |(key, value), values|
      name = key.to_s
      values[name] = value if USAGE_FIELDS.include?(name) && value.is_a?(Numeric)
    end

    details = usage["prompt_tokens_details"] || usage[:prompt_tokens_details]
    if details.is_a?(Hash)
      cached = details["cached_tokens"] || details[:cached_tokens]
      snapshot["prompt_tokens_details"] = {"cached_tokens" => cached} if cached.is_a?(Numeric)
    end

    snapshot
  end

  def measured_call(adapter_class:, prompt:, model:, schema:, validator:, method_name:)
    adapter = adapter_class.new
    started_at = Time.current.utc
    result_status = nil
    error_class = nil

    begin
      response = adapter.public_send(method_name, prompt: prompt, model: model, schema: schema)
      result_status = validator.validate(response).to_a.empty? ? "valid" : "schema_invalid"
    rescue Llm::SchemaError
      result_status = "schema_error"
    rescue Llm::TransportError => error
      result_status = "transport_error"
      error_class = error.class.name
    ensure
      response = adapter.last_response
    end

    upstream_attempts = response.dig("openrouter_metadata", "attempts") if response.is_a?(Hash)
    usage = usage_snapshot(adapter.last_usage)
    {
      "call" => {
        "started_at" => started_at.iso8601,
        "finished_at" => Time.current.utc.iso8601,
        "status" => result_status,
        "actual_model" => response.is_a?(Hash) ? response["model"] : nil,
        "upstream_company" => adapter.last_upstream_company,
        "provider_attempt_count" => upstream_attempts.is_a?(Array) ? upstream_attempts.length : nil,
        "usage" => usage,
        "cache_evidence_status" => cache_evidence_status(usage),
        "error_class" => error_class
      },
      "status" => result_status
    }
  end

  def aggregate_schema_measurement(label:, model:, outcomes:)
    statuses = outcomes.pluck("status")
    success_index = statuses.index("valid")
    calls = outcomes.map { |outcome| outcome.fetch("call") }
    latest = calls.rfind { |call| call["actual_model"].present? } || {}

    {
      "requested_alias" => label,
      "requested_model_id" => model,
      "actual_model" => latest["actual_model"],
      "upstream_company" => latest["upstream_company"],
      "attempts_count" => outcomes.length,
      "first_attempt_valid_count" => (statuses.first == "valid") ? 1 : 0,
      "retry_valid_count" => success_index&.positive? ? 1 : 0,
      "failed_count" => success_index ? 0 : 1,
      "attempts" => calls
    }
  end

  def cache_evidence_status(usage)
    cached = usage.dig("prompt_tokens_details", "cached_tokens") || usage["cached_tokens"] || usage["cache_read_input_tokens"]
    return "not_reported" unless cached.is_a?(Numeric)

    cached.positive? ? "cache_tokens_reported" : "zero_cache_tokens_reported"
  end

  def write(report)
    directory = Rails.root.join("tmp", "openrouter_measurements")
    FileUtils.mkdir_p(directory)
    path = directory.join("#{report.fetch("recorded_at").tr(":", "-")}.json")
    File.write(path, JSON.pretty_generate(report))
    path
  end
end
