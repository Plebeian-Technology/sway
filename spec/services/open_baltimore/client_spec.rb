# frozen_string_literal: true

require "rails_helper"

RSpec.describe OpenBaltimore::Client do
  subject(:client) { described_class.new }

  let(:base) { "https://services1.arcgis.com/UWYHeuuJISiGmgXx/arcgis/rest/services" }
  let(:service) { described_class::COUNCIL_DISTRICT_SERVICE }

  def stub_root(body:, status: 200)
    stub_request(:get, "#{base}/#{service}/FeatureServer")
      .with(query: {"f" => "json"})
      .to_return(status: status, body: body, headers: {"Content-Type" => "application/json"})
  end

  def stub_query(layer_id:, body:, status: 200)
    stub_request(:get, "#{base}/#{service}/FeatureServer/#{layer_id}/query")
      .with(query: {"where" => "1=1", "outFields" => "*", "returnGeometry" => "false", "f" => "json"})
      .to_return(status: status, body: body, headers: {"Content-Type" => "application/json"})
  end

  describe "#council_districts" do
    it "discovers the layer id from the service root, queries it, and returns attribute hashes" do
      stub_root(body: {"layers" => [{"id" => 80, "name" => "Council District"}]}.to_json)
      stub_query(layer_id: 80, body: {
        "features" => [
          {"attributes" => {"AREA_NAME" => "1", "CNTCT_NME" => "Mark Parker"}},
          {"attributes" => {"AREA_NAME" => "2", "CNTCT_NME" => "Danielle McCray"}}
        ]
      }.to_json)

      result = client.council_districts

      expect(result).to eq(
        [
          {"AREA_NAME" => "1", "CNTCT_NME" => "Mark Parker"},
          {"AREA_NAME" => "2", "CNTCT_NME" => "Danielle McCray"}
        ]
      )
    end

    it "raises when the service root exposes no layers" do
      stub_root(body: {"layers" => []}.to_json)

      expect { client.council_districts }.to raise_error(described_class::Error, /no layers/)
    end

    it "raises on an ArcGIS error body returned with HTTP 200" do
      stub_root(body: {"layers" => [{"id" => 80}]}.to_json)
      stub_query(layer_id: 80, body: {"error" => {"code" => 400, "message" => "Invalid URL"}}.to_json)

      expect { client.council_districts }.to raise_error(described_class::Error, /ArcGIS error/)
    end

    it "raises on a non-2xx response" do
      stub_root(body: {"layers" => [{"id" => 80}]}.to_json)
      stub_query(layer_id: 80, body: "nope", status: 503)

      expect { client.council_districts }.to raise_error(described_class::Error, /HTTP 503/)
    end

    it "raises on a non-JSON body" do
      stub_root(body: "<html>down</html>")

      expect { client.council_districts }.to raise_error(described_class::Error, /non-JSON/)
    end
  end
end
