# frozen_string_literal: true

require "rails_helper"

module GooglePlacesClientSpecHelpers
  SEARCH_URL = "https://places.googleapis.com/v1/places:searchText"
  API_KEY = "test-google-maps-key"
  FIELD_MASK = "places.id,places.formattedAddress,places.addressComponents,places.location,places.types"

  BALTIMORE_PLACE = {
    "id" => "ChIJholliday",
    "formattedAddress" => "100 Holliday St, Baltimore, MD 21202, USA",
    "location" => {"latitude" => 39.2904, "longitude" => -76.6122},
    "types" => ["street_address"],
    "addressComponents" => [
      {"longText" => "100", "shortText" => "100", "types" => ["street_number"]},
      {"longText" => "Holliday Street", "shortText" => "Holliday St", "types" => ["route"]},
      {"longText" => "Baltimore", "shortText" => "Baltimore", "types" => ["locality", "political"]},
      {"longText" => "Baltimore City", "shortText" => "Baltimore City", "types" => ["administrative_area_level_2", "political"]},
      {"longText" => "Maryland", "shortText" => "MD", "types" => ["administrative_area_level_1", "political"]},
      {"longText" => "United States", "shortText" => "US", "types" => ["country", "political"]},
      {"longText" => "21202", "shortText" => "21202", "types" => ["postal_code"]}
    ]
  }.freeze

  def self.places_body(*places)
    {"places" => places}.to_json
  end
end

# @lat: [[address-place-classification#Google Places results in the Nominatim shape]]
RSpec.describe GooglePlaces::Client do
  search_url = GooglePlacesClientSpecHelpers::SEARCH_URL
  api_key = GooglePlacesClientSpecHelpers::API_KEY

  around do |example|
    with_env("GOOGLE_MAPS_API_KEY" => api_key) { example.run }
  end

  describe "#search" do
    it "maps a Google place to one Nominatim-shaped place" do
      stub_request(:post, search_url).to_return(
        status: 200,
        body: GooglePlacesClientSpecHelpers.places_body(GooglePlacesClientSpecHelpers::BALTIMORE_PLACE)
      )

      result = described_class.new.search(query: "100 Holliday St")

      expect(result).to eq([
        {
          "place_id" => "ChIJholliday",
          "display_name" => "100 Holliday St, Baltimore, MD 21202, USA",
          "lat" => "39.2904",
          "lon" => "-76.6122",
          "type" => "street_address",
          "source" => "google_places",
          "address" => {
            "house_number" => "100",
            "road" => "Holliday Street",
            "city" => "Baltimore",
            "county" => "Baltimore City",
            "state" => "Maryland",
            "ISO3166-2-lvl4" => "US-MD",
            "postcode" => "21202",
            "country" => "United States",
            "country_code" => "us"
          }
        }
      ])
    end

    it "takes the city from postal_town when there is no locality, and leaves out missing parts" do
      place = {
        "id" => "ChIJlondon",
        "formattedAddress" => "London, UK",
        "location" => {"latitude" => 51.5, "longitude" => -0.12},
        "types" => ["postal_town"],
        "addressComponents" => [
          {"longText" => "London", "shortText" => "London", "types" => ["postal_town"]},
          {"longText" => "United Kingdom", "shortText" => "GB", "types" => ["country", "political"]}
        ]
      }
      stub_request(:post, search_url).to_return(status: 200, body: GooglePlacesClientSpecHelpers.places_body(place))

      result = described_class.new.search(query: "London")

      expect(result&.first&.fetch("address")).to eq(
        "city" => "London",
        "country" => "United Kingdom",
        "country_code" => "gb"
      )
    end

    it "takes the city from sublocality when there is neither locality nor postal_town" do
      place = {
        "id" => "ChIJbrooklyn",
        "formattedAddress" => "Brooklyn, NY, USA",
        "location" => {"latitude" => 40.65, "longitude" => -73.95},
        "types" => ["sublocality"],
        "addressComponents" => [
          {"longText" => "Brooklyn", "shortText" => "Brooklyn", "types" => ["sublocality_level_1", "sublocality", "political"]}
        ]
      }
      stub_request(:post, search_url).to_return(status: 200, body: GooglePlacesClientSpecHelpers.places_body(place))

      result = described_class.new.search(query: "Brooklyn")

      expect(result&.first&.fetch("address")).to eq("city" => "Brooklyn")
    end

    it "sends the key, the field mask, the query, a default page size of 5 and the region code" do
      stub = stub_request(:post, search_url)
        .with(
          headers: {
            "X-Goog-Api-Key" => api_key,
            "X-Goog-FieldMask" => GooglePlacesClientSpecHelpers::FIELD_MASK,
            "Content-Type" => "application/json"
          },
          body: {"textQuery" => "100 Holliday St", "pageSize" => 5, "regionCode" => "us"}
        )
        .to_return(status: 200, body: GooglePlacesClientSpecHelpers.places_body)

      described_class.new.search(query: "100 Holliday St", countrycodes: "us")

      expect(stub).to have_been_made.once
    end

    it "clamps a limit of 50 to a page size of 10" do
      stub = stub_request(:post, search_url)
        .with(body: {"textQuery" => "100 Holliday St", "pageSize" => 10})
        .to_return(status: 200, body: GooglePlacesClientSpecHelpers.places_body)

      described_class.new.search(query: "100 Holliday St", limit: 50)

      expect(stub).to have_been_made.once
    end

    it "builds the rectangle's low and high corners from a left,top,right,bottom viewbox" do
      stub = stub_request(:post, search_url)
        .with(body: hash_including(
          "locationBias" => {
            "rectangle" => {
              "low" => {"latitude" => 39.20, "longitude" => -76.71},
              "high" => {"latitude" => 39.37, "longitude" => -76.53}
            }
          }
        ))
        .to_return(status: 200, body: GooglePlacesClientSpecHelpers.places_body)

      described_class.new.search(query: "100 Holliday St", viewbox: "-76.71,39.37,-76.53,39.20")

      expect(stub).to have_been_made.once
    end

    ["1", 1, true, "true"].each do |bounded|
      it "restricts results to the viewbox when bounded is #{bounded.inspect}" do
        stub = stub_request(:post, search_url)
          .with { |request| JSON.parse(request.body).key?("locationRestriction") && !JSON.parse(request.body).key?("locationBias") }
          .to_return(status: 200, body: GooglePlacesClientSpecHelpers.places_body)

        described_class.new.search(query: "100 Holliday St", viewbox: "-76.71,39.37,-76.53,39.20", bounded: bounded)

        expect(stub).to have_been_made.once
      end
    end

    ["0", 0, false, nil].each do |bounded|
      it "only biases results toward the viewbox when bounded is #{bounded.inspect}" do
        stub = stub_request(:post, search_url)
          .with { |request| JSON.parse(request.body).key?("locationBias") && !JSON.parse(request.body).key?("locationRestriction") }
          .to_return(status: 200, body: GooglePlacesClientSpecHelpers.places_body)

        described_class.new.search(query: "100 Holliday St", viewbox: "-76.71,39.37,-76.53,39.20", bounded: bounded)

        expect(stub).to have_been_made.once
      end
    end

    it "returns an empty array when the answer has no places key" do
      stub_request(:post, search_url).to_return(status: 200, body: "{}")

      expect(described_class.new.search(query: "nowhere at all")).to eq([])
    end

    it "returns nil and sends no request without a key" do
      with_env("GOOGLE_MAPS_API_KEY" => nil) do
        expect(described_class.new.search(query: "100 Holliday St")).to be_nil
      end

      expect(a_request(:post, search_url)).not_to have_been_made
    end

    it "returns nil for a 403 and reports it to Sentry without the query or the key" do
      allow(Sentry).to receive(:capture_message)
      stub_request(:post, search_url).to_return(status: 403, body: '{"error": {"status": "PERMISSION_DENIED"}}')

      expect(described_class.new.search(query: "100 Holliday St")).to be_nil

      expect(Sentry).to have_received(:capture_message).once
        .with("google_places.request_denied", level: :warning, extra: {status: 403})
    end

    it "returns nil for a 429, requests it once, and does not report it" do
      allow(Sentry).to receive(:capture_message)
      stub = stub_request(:post, search_url).to_return(status: 429, body: "Too Many Requests")

      expect(described_class.new.search(query: "100 Holliday St")).to be_nil

      expect(stub).to have_been_made.once
      expect(Sentry).not_to have_received(:capture_message)
    end

    it "returns nil for a connection failure and does not report it" do
      allow(Sentry).to receive(:capture_message)
      stub_request(:post, search_url).to_raise(Faraday::ConnectionFailed.new("connection refused"))

      expect(described_class.new.search(query: "100 Holliday St")).to be_nil

      expect(Sentry).not_to have_received(:capture_message)
    end

    it "returns nil for a 200 answer that is not JSON and does not report it" do
      allow(Sentry).to receive(:capture_message)
      stub_request(:post, search_url).to_return(status: 200, body: "<html>oops</html>")

      expect(described_class.new.search(query: "100 Holliday St")).to be_nil

      expect(Sentry).not_to have_received(:capture_message)
    end

    it "caches nothing: two identical searches make two requests" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      stub = stub_request(:post, search_url)
        .to_return(status: 200, body: GooglePlacesClientSpecHelpers.places_body(GooglePlacesClientSpecHelpers::BALTIMORE_PLACE))

      2.times { described_class.new.search(query: "100 Holliday St") }

      expect(stub).to have_been_made.twice
    end
  end
end
