# frozen_string_literal: true

require "json"

# @lat: [[wikidata-open-baltimore-clients-design#OpenBaltimore::Client: reading council districts]]
module OpenBaltimore
  class Client
    class Error < StandardError; end

    COUNCIL_DISTRICT_SERVICE = "Baltimore_City_Council_District"

    def initialize(connection: nil)
      @conn = connection || Sway::FaradayStack.open_baltimore
    end

    def council_districts
      layer_id = council_district_layer_id
      body = get_json(
        "#{COUNCIL_DISTRICT_SERVICE}/FeatureServer/#{layer_id}/query",
        where: "1=1",
        outFields: "*",
        returnGeometry: "false",
        f: "json"
      )
      features = body["features"] || []
      features.filter_map { |feature| feature["attributes"] }
    end

    private

    # @lat: [[wikidata-open-baltimore-clients-design#OpenBaltimore::Client: reading council districts#Why the layer id is discovered rather than hardcoded]]
    def council_district_layer_id
      root = get_json("#{COUNCIL_DISTRICT_SERVICE}/FeatureServer", f: "json")
      layer = (root["layers"] || []).first
      raise Error, "OpenBaltimore: no layers on #{COUNCIL_DISTRICT_SERVICE} FeatureServer" if layer.nil?

      layer.fetch("id")
    end

    def get_json(resource, **params)
      response = @conn.get(resource, params)
      unless response.status.between?(200, 299)
        raise Error, "OpenBaltimore HTTP #{response.status} for #{resource}: #{response.body.to_s[0, 300]}"
      end

      parsed = parse(response.body)
      # @lat: [[wikidata-open-baltimore-clients-design#OpenBaltimore::Client: reading council districts#Why an ArcGIS error body is checked explicitly]]
      if parsed.is_a?(Hash) && parsed["error"]
        raise Error, "OpenBaltimore ArcGIS error for #{resource}: #{parsed["error"].inspect[0, 300]}"
      end

      parsed
    rescue Faraday::Error => e
      raise Error, "OpenBaltimore transport error for #{resource}: #{e.class.name}: #{e.message.to_s[0, 200]}"
    end

    def parse(body)
      return body if body.is_a?(Hash) || body.is_a?(Array)

      JSON.parse(body.to_s)
    rescue JSON::ParserError => e
      raise Error, "OpenBaltimore returned a non-JSON body: #{e.message.to_s[0, 200]}"
    end
  end
end
