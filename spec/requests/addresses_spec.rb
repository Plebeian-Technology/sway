# frozen_string_literal: true

require "rails_helper"

# @lat: [[address-place-classification#Nominatim place classification and usage constraints]]
RSpec.describe "Addresses", type: :request do
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
        limit: 5
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
        limit: "3"
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
  end
end
