require "faraday"

module Census
  # @lat: [[census-and-geocode-implementation-notes#Why CURRENT_CONGRESS_NUMBER is a constant that needs manual bumping]]
  CURRENT_CONGRESS_NUMBER = 119
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
      @request ||= Faraday.get(query_url, headers: {Accept: "application/json"})
    end

    # @lat: [[census-and-geocode-implementation-notes#Why Census::Congress.data no longer checks for a Hash]]
    def data
      @_data ||= request&.body ? JSON.parse(request.body) : nil
    end

    private

    def query_url
      CENSUS_QUERY_URL
        .sub("<latitude>", @address.latitude.to_s)
        .sub("<longitude>", @address.longitude.to_s)
    end
  end
end
