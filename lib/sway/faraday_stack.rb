# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "faraday/follow_redirects"

# @lat: [[faraday-stack-retry-and-connection-design#Migration history: replacing raw Faraday calls]]
module Sway
  module FaradayStack
    # @lat: [[faraday-stack-retry-and-connection-design#Why TRANSPORT_RETRY_EXCEPTIONS extends the gem default]]
    TRANSPORT_RETRY_EXCEPTIONS = (
      Faraday::Retry::Middleware::DEFAULT_EXCEPTIONS +
      [Faraday::ConnectionFailed, Faraday::SSLError]
    ).freeze

    LEGISTAR_DEFAULTS = {
      max: 3,
      interval: 0.5, # seconds
      backoff_factor: 2,
      retry_statuses: [429, 500, 502, 503, 504],
      methods: %i[get post],
      exceptions: TRANSPORT_RETRY_EXCEPTIONS
    }.freeze #: retry_options

    # @lat: [[download-bounds#Download bounds]]
    LEGISTAR_ATTACHMENT_DEFAULTS = LEGISTAR_DEFAULTS.merge(
      max: 1
    ).freeze #: retry_options

    LLAMACPP_DEFAULTS = {
      max: 2,
      interval: 1.0, # seconds
      backoff_factor: 2,
      retry_statuses: [500, 502, 503, 504],
      methods: %i[post]
    }.freeze #: {max: Integer, interval: Float, backoff_factor: Integer, retry_statuses: Array[Integer], methods: Array[Symbol]}

    # @lat: [[faraday-stack-retry-and-connection-design#OpenRouter retries and upstream User-Agent headers]]
    OPENROUTER_DEFAULTS = {
      max: 2,
      interval: 1.0, # seconds
      backoff_factor: 2,
      retry_statuses: [429],
      methods: %i[post],
      exceptions: TRANSPORT_RETRY_EXCEPTIONS
    }.freeze #: {max: Integer, interval: Float, backoff_factor: Integer, retry_statuses: Array[Integer], methods: Array[Symbol], exceptions: Array[untyped]}

    # @lat: [[legislation-pipeline#The legislation pipeline#Each upstream source gets its own connection profile]]
    GITHUB_DEFAULTS = {
      max: 3,
      interval: 0.5, # seconds
      backoff_factor: 2,
      retry_statuses: [429, 500, 502, 503, 504],
      methods: %i[get],
      exceptions: TRANSPORT_RETRY_EXCEPTIONS
    }.freeze #: retry_options

    # @lat: [[faraday-stack-retry-and-connection-design#OpenRouter retries and upstream User-Agent headers]]
    GITHUB_USER_AGENT = "sway-legislation-pipeline"

    # @lat: [[legislation-pipeline#The legislation pipeline#Each upstream source gets its own connection profile]]
    OPEN_DATA_DEFAULTS = {
      max: 3,
      interval: 0.5, # seconds
      backoff_factor: 2,
      retry_statuses: [429, 500, 502, 503, 504],
      methods: %i[get],
      exceptions: TRANSPORT_RETRY_EXCEPTIONS
    }.freeze #: retry_options

    # @lat: [[faraday-stack-retry-and-connection-design#Why the Nominatim profile does not retry 429]]
    NOMINATIM_DEFAULTS = {
      max: 3,
      interval: 0.5, # seconds
      backoff_factor: 2,
      retry_statuses: [500, 502, 503, 504],
      methods: %i[get],
      exceptions: TRANSPORT_RETRY_EXCEPTIONS
    }.freeze #: retry_options

    # @lat: [[faraday-stack-retry-and-connection-design#OpenRouter retries and upstream User-Agent headers]]
    NOMINATIM_USER_AGENT = "Sway/1.0 (civic-tech-app; https://sway.vote)"

    def self.build(base_url:, timeout_seconds: 30, retry_options: LEGISTAR_DEFAULTS)
      Faraday.new(url: base_url) do |conn|
        conn.request(:retry, retry_options)
        conn.options.timeout = timeout_seconds
        yield conn if block_given?
        conn.adapter(Faraday.default_adapter)
      end
    end

    # @lat: [[attachment-fetch-safety-checks#Why the Legistar Faraday connection does not auto-follow redirects]]
    def self.legistar
      build(
        base_url: Sway::Settings.upstream.legistar_api_base_url
      )
    end

    # @lat: [[download-bounds#Download bounds]]
    def self.legistar_attachment(timeout_seconds: 30)
      build(
        base_url: Sway::Settings.upstream.legistar_api_base_url,
        timeout_seconds: timeout_seconds,
        retry_options: LEGISTAR_ATTACHMENT_DEFAULTS
      )
    end

    # @lat: [[faraday-stack-retry-and-connection-design#Why there is no .llamacpp connection method]]
    # @lat: [[legislation-pipeline#The legislation pipeline#Each upstream source gets its own connection profile]]
    def self.github(timeout_seconds: 60)
      build(
        base_url: Sway::Settings.upstream.law_xml_github_base_url,
        timeout_seconds: timeout_seconds,
        retry_options: GITHUB_DEFAULTS
      ) do |conn|
        conn.headers["User-Agent"] = GITHUB_USER_AGENT
        conn.response(:follow_redirects)
      end
    end

    # @lat: [[faraday-stack-retry-and-connection-design#Migration history: replacing raw Faraday calls]]
    def self.open_states(timeout_seconds: 30)
      build(
        base_url: Sway::Settings.upstream.openstates_api_base_url,
        timeout_seconds: timeout_seconds,
        retry_options: OPEN_DATA_DEFAULTS
      )
    end

    class CongressGovErrorReporter < Faraday::Middleware
      API_KEY_QUERY_REGEXP = %r{(\bapi_key=)[^&#\s]*}i
      MESSAGE = "Congress.gov API HTTP error"

      def on_complete(env)
        return unless env.status && env.status >= 400

        path_template = env.url.path.to_s.gsub(%r{(?<=/)[0-9]+(?=/|$)}, ":n")
        return if env.status == 404 && path_template.end_with?("/house-vote/:n/:n/:n/members")

        sanitized_url = env.url.to_s.gsub(API_KEY_QUERY_REGEXP, '\1[FILTERED]')
        Sentry.capture_message(
          MESSAGE,
          level: :error,
          fingerprint: ["congress_gov_http", env.status.to_s, path_template],
          extra: {
            status: env.status,
            method: env.method,
            path: env.url.path,
            url: sanitized_url
          }
        )
      end
    end

    # @lat: [[faraday-stack-retry-and-connection-design#Migration history: replacing raw Faraday calls]]
    def self.congress_gov(timeout_seconds: 30)
      build(
        base_url: Sway::Settings.upstream.congress_gov_api_base_url,
        timeout_seconds: timeout_seconds,
        retry_options: OPEN_DATA_DEFAULTS
      ) do |conn|
        conn.builder.insert(0, Sway::FaradayStack::CongressGovErrorReporter)
      end
    end

    # @lat: [[faraday-stack-retry-and-connection-design#Why .congress_legislators has a longer timeout]]
    def self.congress_legislators(timeout_seconds: 120)
      build(
        base_url: Sway::Settings.upstream.congress_legislators_base_url,
        timeout_seconds: timeout_seconds,
        retry_options: OPEN_DATA_DEFAULTS
      )
    end

    def self.nominatim(timeout_seconds: 10)
      build(
        base_url: Sway::Settings.upstream.nominatim_api_base_url,
        timeout_seconds: timeout_seconds,
        retry_options: NOMINATIM_DEFAULTS
      ) do |conn|
        conn.headers["User-Agent"] = NOMINATIM_USER_AGENT
        conn.headers["Accept"] = "application/json"
      end
    end

    def self.brave_search(timeout_seconds: 15)
      build(
        base_url: Sway::Settings.upstream.brave_search_api_base_url,
        timeout_seconds: timeout_seconds,
        retry_options: OPEN_DATA_DEFAULTS
      ) do |conn|
        conn.headers["Accept"] = "application/json"
      end
    end
  end
end
