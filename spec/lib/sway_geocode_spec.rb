# frozen_string_literal: true

require "rails_helper"
require "sway_geocode"

RSpec.describe SwayGeocode do
  # Congress and Local used to sit inside `class << self`, which defined them on
  # the module's singleton class, so `SwayGeocode::Congress` did not resolve like
  # a normal nested constant. They now live at the module level, and both resolve
  # from outside.
  describe "class structure" do
    it "exposes Congress and Local as ordinary module-nested classes" do
      expect(SwayGeocode::Congress).to be_a(Class)
      expect(SwayGeocode::Local).to be_a(Class)
    end

    it "does not include the (no-op) Census module in Congress" do
      expect(SwayGeocode::Congress.include?(Census)).to be(false)
    end
  end

  describe ".build" do
    let(:address) { build_stubbed(:address) }

    it "builds a Congress geocoder for a congressional locale" do
      sway_locale = instance_double(SwayLocale, congress?: true)
      expect(SwayGeocode.build(sway_locale, address)).to be_a(SwayGeocode::Congress)
    end

    it "builds a Local geocoder for a non-congressional locale" do
      sway_locale = instance_double(SwayLocale, congress?: false)
      expect(SwayGeocode.build(sway_locale, address)).to be_a(SwayGeocode::Local)
    end
  end

  describe "Congress#districts" do
    subject { SwayGeocode::Congress.new(address).districts }

    let(:address) { build_stubbed(:address, latitude: 39.307411, longitude: -76.615712) }
    let(:census_tigerweb_stub) { stub_request(:get, %r{tigerweb\.geo\.census\.gov/arcgis/rest/services/TIGERweb/}) }

    def expect_census_geocoding_unavailable
      expect { subject }.to raise_error(
        SwayGeocode::ServiceUnavailableError,
        /\ACensus TIGERweb geocoding is unavailable/
      )
    end

    it "raises ServiceUnavailableError for HTTP 502 with an HTML body" do
      census_tigerweb_stub.to_return(status: 502, body: "<html><body>Bad Gateway</body></html>")

      expect_census_geocoding_unavailable
    end

    it "raises ServiceUnavailableError for HTTP 200 with an empty body" do
      census_tigerweb_stub.to_return(status: 200, body: "")

      expect_census_geocoding_unavailable
    end

    it "raises ServiceUnavailableError for HTTP 200 with a body that is not JSON" do
      census_tigerweb_stub.to_return(status: 200, body: "not json")

      expect_census_geocoding_unavailable
    end

    it "raises ServiceUnavailableError for HTTP 200 with an ArcGIS error object" do
      census_tigerweb_stub.to_return(status: 200, body: {error: {code: 500, message: "Unable to complete operation."}}.to_json)

      expect_census_geocoding_unavailable
    end

    it "raises ServiceUnavailableError for HTTP 200 with a JSON array body" do
      census_tigerweb_stub.to_return(status: 200, body: "[]")

      expect_census_geocoding_unavailable
    end

    it "raises ServiceUnavailableError for HTTP 200 with features that are not feature objects" do
      census_tigerweb_stub.to_return(status: 200, body: {features: [{attributes: "x"}]}.to_json)

      expect_census_geocoding_unavailable
    end

    it "raises ServiceUnavailableError when the request times out" do
      census_tigerweb_stub.to_timeout

      expect_census_geocoding_unavailable
    end

    it "returns an empty array for an empty features array" do
      census_tigerweb_stub.to_return(status: 200, body: {features: []}.to_json)

      expect(subject).to eq([])
    end

    it "returns the district pair for a feature in district 07" do
      census_tigerweb_stub.to_return(status: 200, body: {features: [{attributes: {"CD119" => "07"}}]}.to_json)

      expect(subject).to eq([0, 7])
    end
  end

  # @lat: [[census-and-geocode-implementation-notes#Why SwayGeocode::Congress and SwayGeocode::Local are plain nested classes]]
  describe "Local#districts" do
    let(:baltimore) { create(:sway_locale, :baltimore) }

    def local_districts(sway_locale, latitude:, longitude:)
      address = build_stubbed(:address, latitude:, longitude:)
      SwayGeocode::Local.new(sway_locale, address).districts
    end

    it "returns the district pair for City Hall in Baltimore district 11" do
      expect(local_districts(baltimore, latitude: 39.29105, longitude: -76.61069)).to eq([0, 11])
    end

    it "returns an empty array for Towson, just outside the city" do
      expect(local_districts(baltimore, latitude: 39.4015, longitude: -76.6025)).to eq([])
    end

    it "returns an empty array for coordinates 0 and 0" do
      expect(local_districts(baltimore, latitude: 0, longitude: 0)).to eq([])
    end

    it "returns an empty array for a blank latitude and longitude" do
      expect(local_districts(baltimore, latitude: nil, longitude: nil)).to eq([])
    end

    it "returns an empty array and logs once for a locale with no geojson file" do
      maryland = create(:sway_locale, :maryland)
      allow(SwayLogging).to receive(:info)

      expect(local_districts(maryland, latitude: 39.29105, longitude: -76.61069)).to eq([])
      expect(SwayLogging).to have_received(:info).with(/has no geojson file/).once
    end

    it "loads the geojson once for two lookups inside a district" do
      address = build_stubbed(:address, latitude: 39.29105, longitude: -76.61069)
      geocoder = SwayGeocode.build(baltimore, address)
      allow(baltimore).to receive(:load_geojson).and_call_original

      expect([geocoder.districts, geocoder.districts]).to eq([[0, 11], [0, 11]])
      expect(baltimore).to have_received(:load_geojson).once
    end
  end
end
