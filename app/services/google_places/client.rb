# frozen_string_literal: true

module GooglePlaces
  # @lat: [[address-place-classification#Google Places results in the Nominatim shape]]
  class Client
    SEARCH_PATH = "/v1/places:searchText"
    FIELD_MASK = "places.id,places.formattedAddress,places.addressComponents,places.location,places.types"
    DEFAULT_LIMIT = 5
    MAX_LIMIT = 10
    SOURCE = "google_places"
    BOUNDED_VALUES = [true, 1, "1", "true"].freeze

    def initialize(connection: nil)
      @connection = connection || Sway::FaradayStack.google_places
    end

    def search(query:, viewbox: nil, bounded: nil, countrycodes: nil, limit: DEFAULT_LIMIT)
      api_key = EnvSecret.google_maps_api_key
      return nil if api_key.nil?

      body = build_body(query: query.to_s.strip, viewbox: viewbox, bounded: bounded, countrycodes: countrycodes, limit: limit)
      response = @connection.post(
        SEARCH_PATH,
        body.to_json,
        {"X-Goog-Api-Key" => api_key, "X-Goog-FieldMask" => FIELD_MASK, "Content-Type" => "application/json"}
      )
      parse_response(response)
    rescue Faraday::Error => e
      SwayLogging.warn("google_places.fetch_error", error_class: e.class.name)
      nil
    end

    private

    def build_body(query:, viewbox:, bounded:, countrycodes:, limit:)
      body = {
        textQuery: query,
        pageSize: (limit.presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
      } #: Hash[Symbol, untyped]

      region_code = countrycodes.to_s.split(",").first.to_s.strip.downcase
      body[:regionCode] = region_code if region_code.present?

      rectangle = viewbox_rectangle(viewbox)
      if rectangle
        body[BOUNDED_VALUES.include?(bounded) ? :locationRestriction : :locationBias] = {rectangle: rectangle}
      end

      body
    end

    def viewbox_rectangle(viewbox)
      left, top, right, bottom = viewbox.to_s.split(",").map { |value| Float(value.strip, exception: false) }
      return nil if left.nil? || top.nil? || right.nil? || bottom.nil?

      {
        low: {latitude: [top, bottom].min, longitude: [left, right].min},
        high: {latitude: [top, bottom].max, longitude: [left, right].max}
      }
    end

    def parse_response(response)
      if response.status == 403
        SwayLogging.warn("google_places.request_denied", status: response.status)
        Sentry.capture_message("google_places.request_denied", level: :warning, extra: {status: response.status})
        return nil
      end

      unless response.status == 200
        SwayLogging.warn("google_places.http_error", status: response.status)
        return nil
      end

      parsed = JSON.parse(response.body.to_s)
      unless parsed.is_a?(Hash)
        SwayLogging.warn("google_places.unexpected_body", body_class: parsed.class.name)
        return nil
      end

      Array(parsed["places"]).grep(Hash).map { |place| to_nominatim_place(place) }
    rescue JSON::ParserError
      SwayLogging.warn("google_places.unexpected_body", body_class: "String")
      nil
    end

    def to_nominatim_place(place)
      location = place["location"].is_a?(Hash) ? place["location"] : {}
      {
        "place_id" => place["id"],
        "display_name" => place["formattedAddress"],
        "lat" => location["latitude"]&.to_s,
        "lon" => location["longitude"]&.to_s,
        "type" => Array(place["types"]).first,
        "source" => SOURCE,
        "address" => nominatim_address(Array(place["addressComponents"]).grep(Hash))
      }.compact
    end

    def nominatim_address(components)
      country = find_component(components, "country")
      state = find_component(components, "administrative_area_level_1")
      city = find_component(components, "locality") ||
        find_component(components, "postal_town") ||
        find_component(components, "sublocality")
      country_short = country&.dig("shortText")
      state_short = state&.dig("shortText")

      {
        "house_number" => find_component(components, "street_number")&.dig("longText"),
        "road" => find_component(components, "route")&.dig("longText"),
        "city" => city&.dig("longText"),
        "county" => find_component(components, "administrative_area_level_2")&.dig("longText"),
        "state" => state&.dig("longText"),
        "ISO3166-2-lvl4" => (country_short && state_short) ? "#{country_short}-#{state_short}" : nil,
        "postcode" => find_component(components, "postal_code")&.dig("longText"),
        "country" => country&.dig("longText"),
        "country_code" => country_short&.downcase
      }.compact
    end

    def find_component(components, type)
      components.find { |component| Array(component["types"]).include?(type) }
    end
  end
end
