# frozen_string_literal: true

require "digest"

# @lat: [[address-place-classification#Nominatim place classification and usage constraints]]
class NominatimService
  CACHE_EXPIRY = 24.hours
  DEFAULT_LIMIT = 5
  MAX_LIMIT = 10

  class << self
    def search(query:, viewbox: nil, bounded: nil, countrycodes: nil, limit: DEFAULT_LIMIT)
      new.search(
        query: query,
        viewbox: viewbox,
        bounded: bounded,
        countrycodes: countrycodes,
        limit: limit
      )
    end
  end

  def initialize(connection: nil)
    @conn = connection || Sway::FaradayStack.nominatim
  end

  def search(query:, viewbox: nil, bounded: nil, countrycodes: nil, limit: DEFAULT_LIMIT)
    q = query.to_s.strip
    return [] if q.blank?

    clamped_limit = (limit.presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
    params = build_params(query: q, viewbox: viewbox, bounded: bounded, countrycodes: countrycodes, limit: clamped_limit)
    cache_key = build_cache_key(params)

    Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRY, skip_nil: true) do
      fetch_from_nominatim(params)
    end || []
  rescue => e
    SwayLogging.error("nominatim_service.search_failed", error: e.message, query: q)
    []
  end

  private

  def build_params(query:, viewbox:, bounded:, countrycodes:, limit:)
    params = {
      q: query,
      format: "jsonv2",
      addressdetails: 1,
      limit: limit
    }

    if viewbox.present?
      params[:viewbox] = viewbox.to_s.strip
      if bounded.present?
        params[:bounded] = (bounded == true || bounded == "1" || bounded == 1 || bounded == "true") ? 1 : 0
      end
    end

    if countrycodes.present?
      params[:countrycodes] = countrycodes.to_s.strip.downcase
    end

    params
  end

  def build_cache_key(params)
    "nominatim:search:#{Digest::SHA256.hexdigest(params.to_a.sort_by(&:first).to_json)}"
  end

  def fetch_from_nominatim(params)
    response = @conn.get("search", params)
    unless response.status == 200
      SwayLogging.warn("nominatim_service.http_error", status: response.status)
      return nil
    end

    parsed = response.body
    parsed = JSON.parse(parsed) if parsed.is_a?(String)
    unless parsed.is_a?(Array)
      SwayLogging.warn("nominatim_service.unexpected_body", body_class: parsed.class.name)
      return nil
    end

    parsed
  rescue => e
    SwayLogging.warn("nominatim_service.fetch_error", error: e.message)
    nil
  end
end
