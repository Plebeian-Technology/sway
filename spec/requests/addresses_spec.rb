# frozen_string_literal: true

require "rails_helper"

# @lat: [[address-place-classification#Nominatim place classification and usage constraints]]
RSpec.describe "Addresses", type: :request do
  include_context "SessionDouble"

  describe "GET /addresses/autocomplete" do
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

    it "allows unauthenticated access and returns autocomplete suggestions from NominatimService" do
      expect(NominatimService).to receive(:search).with(
        query: "100 Holliday",
        viewbox: nil,
        bounded: nil,
        countrycodes: nil,
        limit: 5,
        google_fallback: false
      ).and_return([sample_place])

      get "/addresses/autocomplete", params: {q: "100 Holliday"}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([sample_place])
    end

    it "forwards viewbox, bounded, countrycodes, and limit parameters to NominatimService" do
      expect(NominatimService).to receive(:search).with(
        query: "100 Holliday",
        viewbox: "-76.7114,39.3720,-76.5297,39.1972",
        bounded: "1",
        countrycodes: "us",
        limit: "3",
        google_fallback: false
      ).and_return([sample_place])

      get "/addresses/autocomplete", params: {
        q: "100 Holliday",
        viewbox: "-76.7114,39.3720,-76.5297,39.1972",
        bounded: "1",
        countrycodes: "us",
        limit: "3"
      }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([sample_place])
    end

    it "lets a signed-in user's search fall back to Google Places" do
      sign_in(create(:user))
      expect(NominatimService).to receive(:search)
        .with(hash_including(query: "100 Holliday", google_fallback: true))
        .and_return([sample_place])

      get "/addresses/autocomplete", params: {q: "100 Holliday"}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([sample_place])
    end

    it "does not ask Google Places for an anonymous search that Nominatim cannot answer" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      stub_request(:get, "https://nominatim.openstreetmap.org/search")
        .with(query: hash_including({}))
        .to_return(status: 429, body: "Too Many Requests")
      google = stub_request(:post, "https://places.googleapis.com/v1/places:searchText")

      with_env("GOOGLE_MAPS_API_KEY" => "test-google-maps-key") do
        get "/addresses/autocomplete", params: {q: "100 Holliday"}
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
      expect(google).not_to have_been_requested
    end

    it "returns an empty array when query is blank without querying NominatimService" do
      expect(NominatimService).not_to receive(:search)

      get "/addresses/autocomplete", params: {q: "  "}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it "throttles after 60 autocomplete requests from the same IP within 1 minute using RATE_LIMIT_STORE" do
      with_rate_limit_enabled(:sign_in) do
        61.times do
          get "/addresses/autocomplete",
            params: {q: "  "},
            headers: {"Accept" => "application/json", "REMOTE_ADDR" => "10.0.5.1"}
        end

        expect(response).to have_http_status(:too_many_requests)
      end
    end

    context "with malformed query parameters" do
      search_url = "https://nominatim.openstreetmap.org/search"
      viewbox = "-76.7114,39.3720,-76.5297,39.1972"

      before do
        stub_request(:get, search_url).with(query: hash_including({}))
          .to_return(status: 200, body: "[]", headers: {"Content-Type" => "application/json"})
      end

      [
        ["q as an array", "q[]=100+Holliday"],
        ["q as a nested hash", "q[a]=100+Holliday"],
        ["a 5000-character q", "q=#{"a" * 5000}"]
      ].each do |description, query_string|
        it "answers an empty array without calling Nominatim for #{description}" do
          get "/addresses/autocomplete?#{query_string}"

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq([])
          expect(a_request(:get, search_url).with(query: hash_including({}))).not_to have_been_made
        end
      end

      [
        ["viewbox as an array", "viewbox[]=#{viewbox}", "viewbox"],
        ["bounded as an array", "viewbox=#{viewbox}&bounded[]=1", "bounded"],
        ["countrycodes as an array", "countrycodes[]=us", "countrycodes"]
      ].each do |description, query_string, dropped_key|
        it "searches without the #{dropped_key} parameter for #{description}" do
          get "/addresses/autocomplete?q=100+Holliday&#{query_string}"

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq([])
          expect(
            a_request(:get, search_url).with(query: hash_including("q" => "100 Holliday", "limit" => "5"))
          ).to have_been_made.once
          expect(a_request(:get, search_url).with(query: hash_excluding(dropped_key))).to have_been_made.once
        end
      end

      [
        ["limit as an array", "limit[]=1"],
        ["limit as a nested hash", "limit[a]=1"]
      ].each do |description, query_string|
        it "searches with the default limit and logs no error for #{description}" do
          expect(SwayLogging).not_to receive(:error)

          get "/addresses/autocomplete?q=100+Holliday&#{query_string}"

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq([])
          expect(a_request(:get, search_url).with(query: hash_including("q" => "100 Holliday", "limit" => "5")))
            .to have_been_made.once
        end
      end

      [
        ["limit abc", "q=100+Holliday&limit=abc", "100 Holliday", "1"],
        ["limit -5", "q=100+Holliday&limit=-5", "100 Holliday", "1"],
        ["limit 99999", "q=100+Holliday&limit=99999", "100 Holliday", "10"],
        ["an accented street name", "q=#{CGI.escape("Calle Peñalver")}", "Calle Peñalver", "5"]
      ].each do |description, query_string, forwarded_query, forwarded_limit|
        it "searches Nominatim with a clamped limit for #{description}" do
          get "/addresses/autocomplete?#{query_string}"

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to eq([])
          expect(
            a_request(:get, search_url).with(query: hash_including("q" => forwarded_query, "limit" => forwarded_limit))
          ).to have_been_made.once
        end
      end
    end
  end

  describe "an unexpected error" do
    before do
      allow(NominatimService).to receive(:search).and_raise(RuntimeError, "boom")
      allow(Sentry).to receive(:capture_exception)
    end

    it "answers 503 onboarding_unavailable and reports the error" do
      get "/addresses/autocomplete", params: {q: "100 Holliday"}, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("error", "code")).to eq("onboarding_unavailable")
      expect(Sentry).to have_received(:capture_exception).with(an_instance_of(RuntimeError), any_args).once
    end
  end
end
