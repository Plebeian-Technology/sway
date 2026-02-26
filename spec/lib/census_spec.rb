# frozen_string_literal: true

require "rails_helper"
require "census"

RSpec.describe Census::Congress do
  let(:address) { build_stubbed(:address, latitude: 39.307411, longitude: -76.615712) }
  subject { described_class.new(address) }

  describe "#request" do
    it "calls the correct Census API URL for the 119th Congress" do
      # Expected URL for 119th Congress (ACS 2024, Layer 54)
      expected_url = "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2024/MapServer/54/query?geometry=-76.615712,39.307411&geometryType=esriGeometryPoint&inSR=4269&spatialRel=esriSpatialRelIntersects&returnGeometry=true&f=json&outFields=STATE,CD119"

      # Mock the response
      response_double = double("Faraday::Response", body: '{}', is_a?: false)
      allow(Faraday).to receive(:get).with(expected_url, headers: {Accept: "application/json"}).and_return(response_double)

      subject.request

      expect(Faraday).to have_received(:get).with(expected_url, headers: {Accept: "application/json"})
    end
  end

  describe "#congressional_district" do
    let(:response_body) do
      {
        "features" => [
          {
            "attributes" => {
              "CD119" => "07"
            }
          }
        ]
      }.to_json
    end

    before do
      response_double = double("Faraday::Response", body: response_body, is_a?: false)
      allow(Faraday).to receive(:get).and_return(response_double)
    end

    it "returns the correct congressional district from the response" do
      expect(subject.congressional_district).to eq("07")
    end
  end
end
