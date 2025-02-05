require "faraday"

module Census
  # TODO: Update to 119 returns data
  # Since we're just using this for geocoding and getting congressional districts, it's not a *huge* deal
  # https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2022/MapServer/50/query?geometry=-76.61571188295052,39.30741100497873&geometryType=esriGeometryPoint&inSR=4269&spatialRel=esriSpatialRelIntersects&returnGeometry=true&f=json&outFields=STATE,CD119
  CONGRESS = 118
  CENSUS_QUERY_URL = "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2022/MapServer/50/query?geometry=<longitude>,<latitude>&geometryType=esriGeometryPoint&inSR=4269&spatialRel=esriSpatialRelIntersects&returnGeometry=true&f=json&outFields=STATE,CD#{CONGRESS}"

  class Congress
    def initialize(address)
      @address = T.let(address, Address)
    end

    def congressional_district
      data&.fetch("features", [])&.first&.dig("attributes", "CD#{CONGRESS}")
    end

    # {
    #     displayFieldName: string;
    #     fieldAliases: { STATE: "STATE"; 119: "119" };
    #     geometryType: "esriGeometryPolygon";
    #     spatialReference: { wkid: number; latestWkid: number };
    #     fields: [
    #         {
    #             name: "STATE";
    #             type: "esriFieldTypeString";
    #             alias: "STATE";
    #             length: 2;
    #         },
    #         {
    #             name: "119";
    #             type: "esriFieldTypeString";
    #             alias: "119";
    #             length: 2;
    #         },
    #     ];
    #     features: [
    #         {
    #             attributes: { STATE: string; 119?: string; CD117?: string; CD116?: string };
    #             geometry: {
    #                 rings: [number, number][][];
    #             };
    #         },
    #     ];
    # }
    def request
      @request ||= Faraday.get(query_url, headers: {Accept: "application/json"})
    end

    def data
      @_data ||= if request.is_a?(Hash)
        request
      else
        request&.body ? JSON.parse(request.body) : nil
      end
    end

    private

    def query_url
      CENSUS_QUERY_URL
        .sub("<latitude>", @address.latitude.to_s)
        .sub("<longitude>", @address.longitude.to_s)
    end
  end
end
