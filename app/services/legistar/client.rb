# frozen_string_literal: true

require "json"

# @lat: [[legistar-client-design#What it wraps]]
module Legistar
  class Client
    DEFAULT_CLIENT = "baltimore"

    # @lat: [[hearing-attachment-discovery-internals#matter_id: why it is coerced strictly, twice]]
    ID_MAX = (2**31) - 1 #: Integer

    class Error < StandardError; end

    # @lat: [[legistar-client-design#Why ParseError and HttpError are separate subclasses of Error]]
    class ParseError < Error; end

    # @lat: [[legistar-client-design#Why ParseError and HttpError are separate subclasses of Error]]
    class HttpError < Error
      attr_reader :status, :path

      # @lat: [[legistar-client-design#Why every response body is scrubbed to valid UTF-8 before anything else sees it]]
      def initialize(status:, path:, body: nil)
        @status = status
        @path = path
        snippet = Sway::Utf8.scrub(body)[0, 300] || ""
        super("Legistar API HTTP #{status} for #{path}#{" — #{snippet}" unless snippet.empty?}")
      end
    end

    attr_reader :client

    def initialize(client: DEFAULT_CLIENT, connection: nil)
      @client = client
      @conn = connection || Sway::FaradayStack.legistar
    end

    def get(resource, **odata)
      get_raw(resource, odata)
    end

    # @lat: [[legistar-client-design#Why odata_params only prefixes Symbol keys with "$"]]
    def get_raw(resource, odata_hash)
      path = "/v1/#{@client}/#{resource}"
      response = @conn.get(path, odata_params(odata_hash))

      raw = response.body

      # @lat: [[legistar-client-design#Why every response body is scrubbed to valid UTF-8 before anything else sees it]]
      raise HttpError.new(status: response.status, path: path, body: Sway::Utf8.scrub(raw)) unless response.status.between?(200, 299)

      # @lat: [[legistar-client-design#Why the already-decoded-body tolerance check lives in get_raw, not parse]]
      return raw if raw.is_a?(::Array) || raw.is_a?(::Hash)

      parse(Sway::Utf8.scrub(raw))
    rescue Faraday::Error => e
      # @lat: [[legistar-client-design#Why every response body is scrubbed to valid UTF-8 before anything else sees it]]
      raise Error,
        "Legistar transport error for #{path}: #{e.class.name}: #{Sway::Utf8.scrub(e.message)[0, 300]}"
    end

    # @lat: [[legistar-client-design#Why only wrappers with real callers are kept]]
    def matters(**odata) = get("Matters", **odata)

    def matter_attachments(matter_id, **odata) = get("Matters/#{coerce_id!(matter_id)}/Attachments", **odata)

    def matter_histories(matter_id, **odata) = get("Matters/#{coerce_id!(matter_id)}/Histories", **odata)

    def person(id)
      body = get("Persons/#{coerce_id!(id)}")
      raise Error, "Legistar: /Persons/#{id} returned #{body.class} (expected a Hash)" unless body.is_a?(::Hash)

      body #: Hash[String, untyped]
    end

    private

    # @lat: [[legistar-client-design#Why odata_params only prefixes Symbol keys with "$"]]
    def odata_params(odata)
      odata.each_with_object({}) do |(key, value), params|
        next if value.nil?

        name = key.is_a?(::Symbol) ? "$#{key}" : key.to_s
        params[name] = value
      end
    end

    def coerce_id!(value)
      case value
      when Integer
        raise Error, "Legistar id must be a positive integer (got #{value})" unless value.positive? && value <= ID_MAX

        value
      when String
        raise Error, "Legistar id must be 1-10 digits (got #{value.inspect})" unless value.match?(/\A\d{1,10}\z/)

        coerced = Integer(value, 10)
        raise Error, "Legistar id out of range (got #{coerced})" unless coerced.positive? && coerced <= ID_MAX

        coerced
      else
        raise Error, "Legistar id must be Integer-coercible (got #{value.class.name})"
      end
    end

    # @lat: [[legistar-client-design#Why every response body is scrubbed to valid UTF-8 before anything else sees it]]
    def parse(body)
      JSON.parse(Sway::Utf8.scrub(body))
    rescue JSON::ParserError => e
      raise ParseError, "Legistar returned a non-JSON body: #{e.message.to_s[0, 200]}"
    end
  end
end
