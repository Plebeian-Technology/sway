# frozen_string_literal: true

require "rails_helper"

# @lat: [[address-place-classification#Nominatim place classification and usage constraints]]
RSpec.describe NominatimService do
  search_url = "https://nominatim.openstreetmap.org/search"
  sample_place = {
    "place_id" => 100149,
    "osm_type" => "node",
    "osm_id" => 107775,
    "lat" => "39.29038",
    "lon" => "-76.61219",
    "display_name" => "100 Holliday St, Baltimore, MD 21202, USA",
    "address" => {
      "house_number" => "100",
      "road" => "Holliday St",
      "city" => "Baltimore",
      "state" => "Maryland",
      "postcode" => "21202",
      "country" => "United States"
    }
  }

  describe ".search" do
    it "queries Nominatim search endpoint with formatted query params and Sway User-Agent" do
      memory_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_cache)

      stub = stub_request(:get, search_url)
        .with(
          query: {
            "q" => "100 Holliday St",
            "format" => "jsonv2",
            "addressdetails" => "1",
            "limit" => "5",
            "viewbox" => "-76.7114,39.3720,-76.5297,39.1972",
            "bounded" => "1",
            "countrycodes" => "us"
          },
          headers: {
            "User-Agent" => "Sway/1.0 (civic-tech-app; https://sway.vote)",
            "Accept" => "application/json"
          }
        )
        .to_return(status: 200, body: [sample_place].to_json, headers: {"Content-Type" => "application/json"})

      results = described_class.search(
        query: "100 Holliday St",
        viewbox: "-76.7114,39.3720,-76.5297,39.1972",
        bounded: true,
        countrycodes: "us"
      )

      expect(stub).to have_been_requested.once
      expect(results).to eq([sample_place])
    end

    it "caches successful responses for identical parameters in Rails.cache" do
      memory_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_cache)

      stub = stub_request(:get, search_url)
        .with(query: hash_including("q" => "100 Holliday St"))
        .to_return(status: 200, body: [sample_place].to_json, headers: {"Content-Type" => "application/json"})

      results1 = described_class.search(query: "100 Holliday St")
      results2 = described_class.search(query: "100 Holliday St")

      expect(stub).to have_been_requested.once
      expect(results1).to eq([sample_place])
      expect(results2).to eq([sample_place])
    end

    it "returns empty array immediately for blank queries without making an HTTP request" do
      expect(described_class.search(query: "")).to eq([])
      expect(described_class.search(query: "   ")).to eq([])
    end

    it "clamps limit between 1 and 10" do
      stub = stub_request(:get, search_url)
        .with(query: hash_including("limit" => "10"))
        .to_return(status: 200, body: [].to_json, headers: {"Content-Type" => "application/json"})

      described_class.search(query: "Main St", limit: 50)
      expect(stub).to have_been_requested.once
    end

    it "handles HTTP 429 rate limit or 5xx upstream responses gracefully by returning empty array" do
      stub_request(:get, search_url)
        .to_return(status: 429, body: "Too Many Requests")

      with_env("GOOGLE_MAPS_API_KEY" => nil) do
        expect(described_class.search(query: "Crash Test")).to eq([])
      end
    end

    it "handles Faraday connection errors gracefully by returning empty array" do
      stub_request(:get, search_url)
        .to_raise(Faraday::ConnectionFailed.new("Failed to connect"))

      with_env("GOOGLE_MAPS_API_KEY" => nil) do
        expect(described_class.search(query: "Offline Test")).to eq([])
      end
    end
  end

  describe ".search after a failed or malformed answer" do
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }
    let(:holliday_url) { search_url }
    let(:holliday_query) { hash_including("q" => "100 Holliday St") }
    let(:success_response) { {status: 200, body: [sample_place].to_json, headers: {"Content-Type" => "application/json"}} }
    let(:place) { sample_place }

    before { allow(Rails).to receive(:cache).and_return(memory_cache) }

    around do |example|
      with_env("GOOGLE_MAPS_API_KEY" => nil) { example.run }
    end

    def search_holliday
      described_class.search(query: "100 Holliday St")
    end

    def expect_next_search_to_reach_nominatim
      expect(search_holliday).to eq([])

      stub_request(:get, holliday_url).with(query: holliday_query).to_return(success_response)

      expect(search_holliday).to eq([place])
    end

    def expect_two_upstream_requests
      expect(a_request(:get, holliday_url).with(query: holliday_query)).to have_been_made.twice
    end

    it "does not cache an HTTP 403 answer" do
      stub_request(:get, search_url).with(query: holliday_query).to_return(status: 403, body: "Forbidden")

      expect_next_search_to_reach_nominatim
      expect_two_upstream_requests
    end

    it "does not cache a connection failure" do
      stub_request(:get, search_url).with(query: holliday_query).to_raise(Faraday::ConnectionFailed.new("Failed to connect"))

      expect_next_search_to_reach_nominatim
    end

    it "does not cache an HTTP 200 answer whose body is an HTML page" do
      stub_request(:get, search_url).with(query: holliday_query)
        .to_return(status: 200, body: "<html><body>Service unavailable</body></html>", headers: {"Content-Type" => "text/html"})

      expect_next_search_to_reach_nominatim
      expect_two_upstream_requests
    end

    it "returns an empty array, not key and value pairs, for an HTTP 200 JSON object and does not cache it" do
      stub_request(:get, search_url).with(query: holliday_query)
        .to_return(status: 200, body: {"error" => "Rate limited"}.to_json, headers: {"Content-Type" => "application/json"})

      expect_next_search_to_reach_nominatim
      expect_two_upstream_requests
    end

    it "caches a genuine empty answer" do
      stub = stub_request(:get, search_url).with(query: holliday_query)
        .to_return(status: 200, body: [].to_json, headers: {"Content-Type" => "application/json"})

      expect([search_holliday, search_holliday]).to eq([[], []])
      expect(stub).to have_been_requested.once
    end
  end

  describe ".search when Nominatim gives no answer" do
    google_url = "https://places.googleapis.com/v1/places:searchText"
    google_place = {
      "id" => "ChIJholliday",
      "formattedAddress" => "100 Holliday St, Baltimore, MD 21202, USA",
      "location" => {"latitude" => 39.2904, "longitude" => -76.6122},
      "types" => ["street_address"],
      "addressComponents" => []
    }
    google_success = {status: 200, body: {"places" => [google_place]}.to_json, headers: {"Content-Type" => "application/json"}}
    let(:holliday_query) { hash_including("q" => "100 Holliday St") }

    before do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    end

    it "returns the Google Places answer when Nominatim answers with an error status" do
      stub_request(:get, search_url).with(query: holliday_query).to_return(status: 429, body: "Too Many Requests")
      google = stub_request(:post, google_url).to_return(google_success)

      results = with_env("GOOGLE_MAPS_API_KEY" => "test-google-maps-key") do
        described_class.search(query: "100 Holliday St")
      end

      expect(google).to have_been_requested.once
      expect(results.map { |result| result.values_at("place_id", "source") }).to eq([["ChIJholliday", "google_places"]])
    end

    it "asks Nominatim again on the next search once it recovers, without caching the Google answer" do
      stub_request(:get, search_url).with(query: holliday_query)
        .to_return(status: 429, body: "Too Many Requests").then
        .to_return(status: 200, body: [sample_place].to_json, headers: {"Content-Type" => "application/json"})
      google = stub_request(:post, google_url).to_return(google_success)

      first, second = with_env("GOOGLE_MAPS_API_KEY" => "test-google-maps-key") do
        [described_class.search(query: "100 Holliday St"), described_class.search(query: "100 Holliday St")]
      end

      expect(first.pluck("source")).to eq(["google_places"])
      expect(second).to eq([sample_place])
      expect(google).to have_been_requested.once
    end

    it "does not ask Google when Nominatim answers with a genuine empty array" do
      stub_request(:get, search_url).with(query: holliday_query)
        .to_return(status: 200, body: [].to_json, headers: {"Content-Type" => "application/json"})
      google = stub_request(:post, google_url).to_return(google_success)

      results = with_env("GOOGLE_MAPS_API_KEY" => "test-google-maps-key") do
        described_class.search(query: "100 Holliday St")
      end

      expect(results).to eq([])
      expect(google).not_to have_been_requested
    end

    it "returns an empty array without asking Google when there is no Google key" do
      stub_request(:get, search_url).with(query: holliday_query).to_return(status: 429, body: "Too Many Requests")
      google = stub_request(:post, google_url).to_return(google_success)

      results = with_env("GOOGLE_MAPS_API_KEY" => nil) do
        described_class.search(query: "100 Holliday St")
      end

      expect(results).to eq([])
      expect(google).not_to have_been_requested
    end

    it "returns an empty array when Google fails too" do
      stub_request(:get, search_url).with(query: holliday_query).to_return(status: 429, body: "Too Many Requests")
      google = stub_request(:post, google_url).to_return(status: 400, body: {"error" => {"status" => "INVALID_ARGUMENT"}}.to_json)

      results = with_env("GOOGLE_MAPS_API_KEY" => "test-google-maps-key") do
        described_class.search(query: "100 Holliday St")
      end

      expect(results).to eq([])
      expect(google).to have_been_requested.once
    end
  end
end
