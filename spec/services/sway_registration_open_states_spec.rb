# frozen_string_literal: true

require "rails_helper"

# The OpenStates lookup was a bare Faraday.get with no timeout/retry. A
# non-2xx or missing results key made nil.filter raise past the rescue — a
# permanent failure. It now raises or returns [].
RSpec.describe SwayRegistrationService, "#find_legislators_from_open_states_geo_endpoint" do
  # Named in full, not just region: the factory picks a city from a
  # rotating list, so state: MD alone could build a hybrid jurisdiction
  # that exists nowhere and declares no term rules.
  let(:sway_locale) do
    create(:sway_locale, city: "maryland", state: "MD", country: "united_states")
  end
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:address) { create(:address, latitude: 39.29, longitude: -76.61) }
  let(:user) { create(:user) }
  let(:service) do
    described_class.new(user, address, sway_locale, invited_by_id: nil, async: false)
  end

  before { ENV["OPEN_STATES_API_KEY"] = "test-key" }
  after { ENV.delete("OPEN_STATES_API_KEY") }

  it "raises ServiceUnavailableError on a non-2xx response instead of NoMethodError" do
    conn = Faraday.new do |c|
      c.adapter(:test) do |stub|
        stub.get("people.geo") { [429, {"Content-Type" => "application/json"}, '{"error":"rate limited"}'] }
      end
    end
    allow(Sway::FaradayStack).to receive(:open_states).and_return(conn)

    expect {
      service.send(:find_legislators_from_open_states_geo_endpoint)
    }.to raise_error(SwayGeocode::ServiceUnavailableError, /HTTP 429/)
  end

  it "returns [] for a 200 response with no results key (keyless body degrades)" do
    conn = Faraday.new do |c|
      c.adapter(:test) do |stub|
        stub.get("people.geo") { [200, {"Content-Type" => "application/json"}, "{}"] }
      end
    end
    allow(Sway::FaradayStack).to receive(:open_states).and_return(conn)

    expect(service.send(:find_legislators_from_open_states_geo_endpoint)).to eq([])
  end

  it "returns the locale legislator whose external_id matches a region-matched result" do
    legislator = create(:legislator, district: district, external_id: "ocd-person/abc", active: true)
    # SwayLocale#legislators now selects Legislator.serving, worked out
    # from terms, not the removed active column — give this legislator a
    # term so the fixture still counts as a match.
    create(:legislator_term, legislator:, district:)
    body = {results: [{id: "ocd-person/abc", jurisdiction: {name: "Maryland"}}]}.to_json
    conn = Faraday.new do |c|
      c.adapter(:test) do |stub|
        stub.get("people.geo") { [200, {"Content-Type" => "application/json"}, body] }
      end
    end
    allow(Sway::FaradayStack).to receive(:open_states).and_return(conn)

    expect(service.send(:find_legislators_from_open_states_geo_endpoint)).to include(legislator)
  end

  it "sends no request for an address without coordinates and still resolves the locale-wide officers" do
    stub_request(:get, /people\.geo/).to_return(status: 200, body: {results: []}.to_json)
    allow(Geocoder).to receive(:search).and_return([])
    unlocated = create(:address, region_code: "MD")
    state_wide = create(:district, sway_locale:, name: "MD0")
    seat = Seat.create!(district: state_wide, seat_identifier: "maryland-governor", title: "Governor", chamber: "Executive")
    governor = create(:legislator, sway_locale:, last_name: "Governor")
    create(:legislator_term, legislator: governor, district: state_wide, seat:)
    unlocated_service = described_class.new(user, unlocated, sway_locale, invited_by_id: nil, async: false)

    expect(unlocated_service.send(:find_legislators_from_open_states_geo_endpoint)).to eq([])
    expect(unlocated_service.district_legislators).to contain_exactly(governor)
    expect(a_request(:get, /people\.geo/)).not_to have_been_made
  end
end
