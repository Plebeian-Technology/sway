# frozen_string_literal: true

require "json"

# @lat: [[open-legislator-client#Why Open Legislator API access uses a native client with Legistar fallback]]
module OpenLegislator
  class Client
    DEFAULT_BASE_URL = "http://localhost:3000/api/v1"
    MAX_LIMIT = 200

    class Error < StandardError; end
    class ParseError < Error; end

    class HttpError < Error
      attr_reader :status, :path, :body

      def initialize(status:, path:, body: nil)
        @status = status
        @path = path
        @body = body
        snippet = Sway::Utf8.scrub(body)[0, 300] || ""
        super("Open Legislator API HTTP #{status} for #{path}#{" — #{snippet}" unless snippet.empty?}")
      end
    end

    attr_reader :base_url, :conn

    def initialize(base_url: DEFAULT_BASE_URL, connection: nil)
      @base_url = base_url.to_s.chomp("/")
      @conn = connection || Sway::FaradayStack.build(base_url: @base_url) do |conn|
        conn.headers["Accept"] = "application/json"
      end
    end

    def get(resource, **params)
      get_raw(resource, params)
    end

    def get_raw(resource, params = {})
      path = normalize_path(resource)
      response = @conn.get(path, clean_params(params))

      raw = response.body
      unless response.status.between?(200, 299)
        raise HttpError.new(status: response.status, path: path, body: Sway::Utf8.scrub(raw))
      end

      return raw if raw.is_a?(::Array) || raw.is_a?(::Hash)

      parse(Sway::Utf8.scrub(raw))
    rescue Faraday::Error => e
      raise Error,
        "Open Legislator transport error for #{path}: #{e.class.name}: #{Sway::Utf8.scrub(e.message)[0, 300]}"
    end

    def matter_by_file_number(file_number)
      return nil if file_number.blank?

      envelope = matters(file_number: file_number.to_s.strip, limit: 1)
      rows = envelope.is_a?(Hash) ? envelope["data"] : []
      return nil unless rows.is_a?(Array) && rows.any?

      first_row = rows.first
      slug = first_row.is_a?(Hash) ? first_row["slug"] : nil
      return nil if slug.blank?

      matter(slug)
    rescue HttpError => e
      return nil if e.status == 404

      raise
    end

    def matter(slug)
      raise ArgumentError, "slug is required" if slug.blank?

      response = get("matters/#{slug}")
      if response.is_a?(Hash) && response.key?("data")
        response["data"]
      else
        response
      end
    end

    def matters(page: 1, limit: 50, **filters)
      params = filters.compact
      params[:page] = page if page
      params[:limit] = limit if limit
      get("matters", **params)
    end

    def meeting(slug)
      raise ArgumentError, "slug is required" if slug.blank?

      response = get("meetings/#{slug}")
      if response.is_a?(Hash) && response.key?("data")
        response["data"]
      else
        response
      end
    end

    def meetings(page: 1, limit: 50, **filters)
      params = filters.compact
      params[:page] = page if page
      params[:limit] = limit if limit
      get("meetings", **params)
    end

    def all_matters(page_size: 50, max_pages: 100, **filters)
      page_size = page_size.to_i.clamp(1, MAX_LIMIT)
      max_pages = max_pages.to_i.clamp(1, 10_000)
      rows = []
      current_page = 1

      max_pages.times do
        envelope = matters(page: current_page, limit: page_size, **filters)
        page_rows = envelope.is_a?(Hash) ? envelope["data"] : nil
        break unless page_rows.is_a?(Array) && page_rows.any?

        rows.concat(page_rows)

        paging = envelope["page"] || {}
        last_page = paging["last"] || paging[:last]
        break if last_page.nil? || current_page >= last_page

        current_page += 1
      end

      rows
    end

    def matter_actions(file_number_or_slug)
      return [] if file_number_or_slug.blank?

      resolved = matter_by_file_number(file_number_or_slug)
      resolved ||= begin
        matter(file_number_or_slug)
      rescue HttpError
        nil
      end

      resolved.is_a?(Hash) ? Array(resolved["actions"]) : []
    end

    private

    def normalize_path(resource)
      res = resource.to_s.sub(%r{\A/}, "")
      res.start_with?("api/v1/") ? "/#{res}" : "/api/v1/#{res}"
    end

    def clean_params(params)
      params.each_with_object({}) do |(key, value), acc|
        acc[key.to_s] = value unless value.nil?
      end
    end

    def parse(body)
      JSON.parse(Sway::Utf8.scrub(body))
    rescue JSON::ParserError => e
      raise ParseError, "Open Legislator returned a non-JSON body: #{e.message.to_s[0, 200]}"
    end
  end
end
