# frozen_string_literal: true

require "rails_helper"
require "census"

RSpec.describe Census::Congress do
  subject do
    Census::Congress.new(
      build_stubbed(:address, latitude: 39.307411, longitude: -76.615712)
    )
  end

  let(:census_query_url) do
    "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2024/MapServer/54/query?geometry=-76.615712,39.307411&geometryType=esriGeometryPoint&inSR=4269&spatialRel=esriSpatialRelIntersects&returnGeometry=true&f=json&outFields=STATE,CD119"
  end

  describe "#request" do
    it "calls the 119th Congress URL with an Accept header and no headers query parameter" do
      stub = stub_request(:get, census_query_url)
        .with(headers: {"Accept" => "application/json"})
        .to_return(status: 200, body: "{}")

      subject.request

      expect(stub).to have_been_requested
    end

    it "sets open and read timeouts of at most 10 seconds" do
      stub_request(:get, census_query_url).to_return(status: 200, body: "{}")
      allow(Faraday).to receive(:new).and_call_original

      subject.request

      expect(Faraday).to have_received(:new).with(
        hash_including(request: {open_timeout: be <= 10, timeout: be <= 10})
      )
    end
  end

  describe "#congressional_district" do
    it "returns the congressional district from the response" do
      stub_request(:get, census_query_url).to_return(
        status: 200,
        body: {features: [{attributes: {"CD119" => "07"}}]}.to_json
      )

      expect(subject.congressional_district).to eq("07")
    end

    it "returns nil for a feature without attributes" do
      stub_request(:get, census_query_url).to_return(status: 200, body: {features: [{}]}.to_json)

      expect(subject.congressional_district).to be_nil
    end

    [
      {features: "x"},
      {features: [1]},
      {features: [{attributes: "x"}]}
    ].each do |body|
      it "raises Faraday::ParsingError for #{body.to_json}" do
        stub_request(:get, census_query_url).to_return(status: 200, body: body.to_json)

        expect { subject.congressional_district }.to raise_error(Faraday::ParsingError)
      end
    end
  end
end
