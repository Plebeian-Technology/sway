# frozen_string_literal: true

require "uri"

module Legistar
  # @lat: [[legistar-detail-url-resolution#Architectural resolution service]]
  class DetailUrlResolver
    DEFAULT_HOST = "baltimore.legistar.com"
    # @lat: [[legistar-detail-url-resolution#Gateway redirection as the reproducible source]]
    GATEWAY_PATH = "/Gateway.aspx"
    REDIRECT_STATUSES = [301, 302, 303].freeze
    ID_MAX = (2**31) - 1 #: Integer
    RETRY_METHODS = (Array(Sway::FaradayStack::LEGISTAR_DEFAULTS[:methods]) + [:head]).uniq.freeze
    RETRY_OPTIONS = Sway::FaradayStack::LEGISTAR_DEFAULTS.merge(
      methods: RETRY_METHODS
    ).freeze #: Sway::FaradayStack::retry_options

    def self.resolve(matter_id, host: DEFAULT_HOST, connection: nil, http_method: :head)
      new(host: host, connection: connection, http_method: http_method).resolve(matter_id)
    end

    def initialize(host: DEFAULT_HOST, connection: nil, http_method: :head)
      @host = (host.presence || DEFAULT_HOST).to_s.strip.downcase
      @http_method = (http_method == :get) ? :get : :head
      @connection = connection || Sway::FaradayStack.build(
        base_url: "https://#{@host}",
        timeout_seconds: 10,
        retry_options: RETRY_OPTIONS
      )
      @cache = {}
    end

    def resolve(matter_id)
      coerced_id = coerce_id(matter_id)
      if coerced_id.nil?
        SwayLogging.warn("[Legistar::DetailUrlResolver] invalid matter_id: #{matter_id.inspect}")
        return nil
      end

      return @cache[coerced_id] if @cache.key?(coerced_id)

      unless valid_host?(@host)
        SwayLogging.warn("[Legistar::DetailUrlResolver] disallowed host: #{@host.inspect}")
        return nil
      end

      resolved = execute_resolution(coerced_id)
      @cache[coerced_id] = resolved if resolved
      resolved
    end

    private

    def execute_resolution(coerced_id)
      query_params = {"M" => "L", "ID" => coerced_id.to_s}

      response = if @http_method == :get
        @connection.get(GATEWAY_PATH, query_params)
      else
        @connection.head(GATEWAY_PATH, query_params)
      end

      unless REDIRECT_STATUSES.include?(response.status)
        SwayLogging.info(
          "[Legistar::DetailUrlResolver] non-redirect response status=#{response.status} for matter_id=#{coerced_id}"
        )
        return nil
      end

      raw_location = response.headers["location"]
      if raw_location.blank?
        SwayLogging.warn(
          "[Legistar::DetailUrlResolver] redirect status=#{response.status} missing Location header for matter_id=#{coerced_id}"
        )
        return nil
      end

      location = Sway::Utf8.scrub(raw_location).strip
      target_uri = URI.join("https://#{@host}", location)
      target_url = target_uri.to_s

      if !target_uri.is_a?(URI::HTTPS) || target_uri.userinfo.present? || !valid_destination_host?(target_uri.host)
        SwayLogging.warn(
          "[Legistar::DetailUrlResolver] unexpected redirect destination: #{target_url.inspect} for matter_id=#{coerced_id}"
        )
        return nil
      end

      unless valid_detail_url?(target_url)
        SwayLogging.warn(
          "[Legistar::DetailUrlResolver] unexpected redirect destination: #{target_url.inspect} for matter_id=#{coerced_id}"
        )
        return nil
      end

      target_url
    rescue Faraday::Error => e
      SwayLogging.warn(
        "[Legistar::DetailUrlResolver] transport error for matter_id=#{coerced_id}: #{e.class}: #{Sway::Utf8.scrub(e.message)[0, 200]}"
      )
      nil
    rescue URI::Error, ArgumentError => e
      SwayLogging.warn(
        "[Legistar::DetailUrlResolver] URI resolution error for matter_id=#{coerced_id}: #{e.class}: #{e.message}"
      )
      nil
    end

    def coerce_id(value)
      case value
      when Integer
        value if value.positive? && value <= ID_MAX
      when String
        trimmed = value.strip
        if trimmed.match?(/\A\d{1,10}\z/)
          coerced = Integer(trimmed, 10)
          coerced if coerced.positive? && coerced <= ID_MAX
        end
      end
    rescue ArgumentError
      nil
    end

    def valid_host?(host)
      host.match?(Legistar::AttachmentUrl::ALLOWED_HOST)
    end

    def valid_destination_host?(host)
      return false if host.blank?

      downcased = host.downcase
      (downcased == @host) || valid_host?(downcased)
    end

    def valid_detail_url?(url)
      return false if url.blank?

      uri = URI.parse(url)
      return false unless uri.is_a?(URI::HTTPS)
      return false if uri.userinfo.present?
      return false unless valid_destination_host?(uri.host)
      path = uri.path
      return false if path.nil?
      return false unless path == "/LegislationDetail.aspx" || path.end_with?("/LegislationDetail.aspx")
      query = uri.query
      return false if query.blank?

      params = URI.decode_www_form(query).to_h
      return false unless params["ID"]&.match?(/\A\d+\z/)
      return false unless params["GUID"]&.match?(/\A[A-Za-z0-9-]+\z/)

      true
    rescue URI::Error, ArgumentError
      false
    end
  end
end
