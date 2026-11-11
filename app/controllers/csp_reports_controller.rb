# frozen_string_literal: true

class CspReportsController < ApplicationController
  skip_before_action :authenticate_sway_user!
  skip_before_action :verify_authenticity_token
  skip_before_action :is_api_request_and_is_route_api_accessible?

  ACCEPTED_TYPES = %w[application/csp-report application/reports+json].freeze
  MAX_BODY_BYTES = 1.megabyte
  SAMPLE_RATIO = 10

  # @lat: [[system-shape#Why CspReportsController filters extension violations and normalizes report payloads]]
  EXTENSION_URI_PATTERN = %r{\A(moz-extension|chrome-extension|safari-extension|safari-web-extension|webkit-masked-url|edge-extension|opera-extension)(:|\z)}i

  # @lat: [[identity-and-access#The rate limit store swaps in after boot]]
  rate_limit to: 100, within: 1.minute,
    by: -> { request.remote_ip },
    only: :create,
    if: -> { RateLimitConfig.enabled?(:csp_report) },
    with: -> { head :too_many_requests },
    store: ApplicationController::RATE_LIMIT_STORE

  def create
    return head :unsupported_media_type unless ACCEPTED_TYPES.include?(request.media_type)
    return head :content_too_large if request.content_length.to_i > MAX_BODY_BYTES

    raw = read_bounded_body
    return head :content_too_large if raw.bytesize > MAX_BODY_BYTES

    report = parse_report(raw)
    fields = extract_fields(report)
    return head :no_content if extension_violation?(fields)

    SwayLogging.warn("csp.violation", **fields)
    forward_to_sentry_sampled(report) if Rails.env.production?
    head :no_content
  end

  private

  def read_bounded_body
    body = request.body
    body.rewind if body.respond_to?(:rewind)
    body.read(MAX_BODY_BYTES + 1).to_s
  end

  def parse_report(raw)
    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

  def normalize_report(report)
    if report.is_a?(Array)
      empty_body = {}
      # @type var empty_body: Hash[String, untyped]
      first_body = report.first.is_a?(Hash) ? (report.first["body"] || empty_body) : empty_body
      body = first_body
      {
        "blocked-uri" => body["blockedURL"] || body["blocked-uri"],
        "violated-directive" => body["effectiveDirective"] || body["violatedDirective"] || body["violated-directive"],
        "document-uri" => body["documentURL"] || body["document-uri"],
        "source-file" => body["sourceFile"] || body["source-file"]
      }
    elsif report.is_a?(Hash)
      report["csp-report"].is_a?(Hash) ? report["csp-report"] : report
    else
      {}
    end
  end

  def extract_fields(report)
    r = normalize_report(report)
    {
      blocked_uri: r["blocked-uri"],
      violated_directive: r["violated-directive"],
      document_uri: r["document-uri"],
      source_file: r["source-file"],
      remote_ip: request.remote_ip
    }
  end

  def extension_violation?(fields)
    [fields[:source_file], fields[:blocked_uri], fields[:document_uri]]
      .any? { |v| v.is_a?(String) && EXTENSION_URI_PATTERN.match?(v) }
  end

  def forward_to_sentry_sampled(report)
    r = normalize_report(report)
    dedupe_key = Digest::SHA256.hexdigest([r["blocked-uri"], r["violated-directive"]].compact.join("|"))
    counter_key = "csp_sentry:#{dedupe_key}:#{Time.current.strftime("%Y%m%d%H")}"
    count = Rails.cache.increment(counter_key, 1, expires_in: 1.hour).to_i
    return unless count == 1 || (count % SAMPLE_RATIO).zero?

    extra = report.is_a?(Hash) ? report : {report: report}
    Sentry.capture_message(
      "CSP Violation: #{r["violated-directive"]}",
      level: :warning,
      extra: extra
    )
  end
end
