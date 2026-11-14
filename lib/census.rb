require "faraday"

module Census
  # @lat: [[census-and-geocode-implementation-notes#Why CURRENT_CONGRESS_NUMBER is a constant that needs manual bumping]]
  CURRENT_CONGRESS_NUMBER = 119
  REQUEST_TIMEOUT_SECONDS = 5
  CENSUS_QUERY_URL = "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2024/MapServer/54/query?geometry=<longitude>,<latitude>&geometryType=esriGeometryPoint&inSR=4269&spatialRel=esriSpatialRelIntersects&returnGeometry=true&f=json&outFields=STATE,CD#{CURRENT_CONGRESS_NUMBER}"

  class Congress
    def initialize(address)
      @address = address
    end

    def congressional_district
      default_features = []
      # @type var default_features: Array[untyped]
      data&.fetch("features", default_features)&.first&.dig("attributes", "CD#{CURRENT_CONGRESS_NUMBER}")
    end

    # @lat: [[census-tigerweb-response-shape#Census TIGERweb query response shape]]
    def request
      @request ||= begin
        response = Faraday.new(request: {open_timeout: REQUEST_TIMEOUT_SECONDS, timeout: REQUEST_TIMEOUT_SECONDS})
          .get(query_url, nil, {Accept: "application/json"})
        raise Faraday::ServerError, "HTTP #{response.status}" unless response.success?

        response
      end
    end

    # @lat: [[census-and-geocode-implementation-notes#Why Census::Congress.data no longer checks for a Hash]]
    def data
      @_data ||= parse(request.body)
    end

    private

    def parse(body)
      raise Faraday::ParsingError, "empty body" if body.blank?

      parsed = JSON.parse(body)
      raise Faraday::ParsingError, "body is not a JSON object" unless parsed.is_a?(Hash)
      raise Faraday::ParsingError, "error object: #{parsed["error"].to_json}" if parsed.key?("error")
      raise Faraday::ParsingError, "features is not a list of feature objects" if parsed.key?("features") && !feature_list?(parsed["features"])

      parsed
    rescue JSON::ParserError => e
      raise Faraday::ParsingError, e
    end

    def feature_list?(features)
      features.is_a?(Array) && features.all? do |feature|
        feature.is_a?(Hash) && (feature["attributes"].nil? || feature["attributes"].is_a?(Hash))
      end
    end

    def query_url
      CENSUS_QUERY_URL
        .sub("<latitude>", @address.latitude.to_s)
        .sub("<longitude>", @address.longitude.to_s)
    end
  end
end
