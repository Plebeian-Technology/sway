require 'faraday'

module Census
  CONGRESS = 118
  CENSUS_QUERY_URL = "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2022/MapServer/50/query?geometry=<longitude>,<latitude>&geometryType=esriGeometryPoint&inSR=4269&spatialRel=esriSpatialRelIntersects&returnGeometry=true&f=json&outFields=STATE,CD#{CONGRESS}"

  class Congress
    def initialize(address)
      @address = T.let(address, Address)
    end

    def congressional_district
      request&.fetch("features", []).first&.dig("attributes", "CD#{CONGRESS}")
    end


    # {
    #     displayFieldName: string;
    #     fieldAliases: { STATE: "STATE"; CD118: "CD118" };
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
    #             name: "CD118";
    #             type: "esriFieldTypeString";
    #             alias: "CD118";
    #             length: 2;
    #         },
    #     ];
    #     features: [
    #         {
    #             attributes: { STATE: string; CD118?: string; CD117?: string; CD116?: string };
    #             geometry: {
    #                 rings: [number, number][][];
    #             };
    #         },
    #     ];
    # }
    def request
      @request ||= Faraday.get(query_url, headers: { "Accept": 'application/json' })
    end

    private

    def query_url
      CENSUS_QUERY_URL
        .sub('<latitude>', @address.latitude.to_s)
        .sub('<longitude>', @address.longitude.to_s)
    end
  end
end
