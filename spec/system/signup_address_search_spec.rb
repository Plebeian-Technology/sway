# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Signup address search", type: :system, js: true do
  let(:user) { create(:user, is_registration_complete: false, registration_status: "pending") }

  let(:sample_place) do
    {
      "place_id" => 100149,
      "lat" => "39.29038",
      "lon" => "-76.61219",
      "display_name" => "100 Holliday St, Baltimore, MD 21202, USA",
      "address" => {
        "house_number" => "100",
        "road" => "Holliday St",
        "city" => "Baltimore",
        "state" => "Maryland",
        "postcode" => "21202",
        "country" => "United States",
        "country_code" => "us",
        "ISO3166-2-lvl4" => "US-MD"
      }
    }
  end

  let(:towson_place) do
    {
      "place_id" => 200250,
      "lat" => "39.4015",
      "lon" => "-76.6019",
      "display_name" => "1 Allegheny Ave, Towson, MD 21204, USA",
      "address" => {
        "house_number" => "1",
        "road" => "Allegheny Ave",
        "city" => "Towson",
        "state" => "Maryland",
        "postcode" => "21204",
        "country" => "United States",
        "country_code" => "us",
        "ISO3166-2-lvl4" => "US-MD"
      }
    }
  end

  around do |example|
    with_env("GOOGLE_MAPS_API_KEY" => nil) do
      example.run
    end
  end

  before do
    sign_in_as(user)
    visit sway_registration_index_path
    wait_until_loaded
    expect(page).to have_field("Address")
  end

  # @lat: [[lat.md/explanation/signup-address-search-browser-tests#Signup address search browser tests#No results]]
  it "displays a no-results message and hides the listbox when search finds nothing" do
    stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
      .to_return(
        status: 200,
        body: [].to_json,
        headers: {"Content-Type" => "application/json"}
      )

    fill_in "Address", with: "zzzz nowhere"

    expect(page).to have_css(
      "[data-testid='address-search-message']",
      text: "No matching addresses found. You can still submit the address as you typed it."
    )
    expect(page).to have_no_css("[role='listbox']")
    expect(page).to have_css("[data-testid='btn-submit-registration']:not([disabled])")
  end

  describe "upstream failures" do
    # @lat: [[lat.md/explanation/signup-address-search-browser-tests#Signup address search browser tests#Upstream failures#Upstream HTTP 429]]
    it "displays the no-results message and leaves the page usable on upstream 429" do
      stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
        .to_return(status: 429, body: "Too Many Requests")

      fill_in "Address", with: "429 Test Ave"

      expect(page).to have_css(
        "[data-testid='address-search-message']",
        text: "No matching addresses found. You can still submit the address as you typed it."
      )
      expect(page).to have_no_css("[role='listbox']")
      expect(page).to have_css("[data-testid='btn-submit-registration']:not([disabled])")
    end

    # @lat: [[lat.md/explanation/signup-address-search-browser-tests#Signup address search browser tests#Upstream failures#Upstream HTTP 500]]
    it "displays the no-results message and leaves the page usable on upstream 500" do
      stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
        .to_return(status: 500, body: "Internal Server Error")

      fill_in "Address", with: "500 Test Ave"

      expect(page).to have_css(
        "[data-testid='address-search-message']",
        text: "No matching addresses found. You can still submit the address as you typed it."
      )
      expect(page).to have_no_css("[role='listbox']")
      expect(page).to have_css("[data-testid='btn-submit-registration']:not([disabled])")
    end

    # @lat: [[lat.md/explanation/signup-address-search-browser-tests#Signup address search browser tests#Upstream failures#Upstream timeout]]
    it "displays the no-results message and leaves the page usable on upstream timeout" do
      stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
        .to_timeout

      fill_in "Address", with: "Timeout Test Ave"

      expect(page).to have_css(
        "[data-testid='address-search-message']",
        text: "No matching addresses found. You can still submit the address as you typed it."
      )
      expect(page).to have_no_css("[role='listbox']")
      expect(page).to have_css("[data-testid='btn-submit-registration']:not([disabled])")
    end
  end

  context "with in-memory Rails.cache" do
    include_context "with in-memory Rails.cache"

    # @lat: [[lat.md/explanation/signup-address-search-browser-tests#Signup address search browser tests#Recovery]]
    it "recovers on subsequent search without caching the failed lookup" do
      stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
        .to_return(status: 500, body: "Internal Server Error")
        .then
        .to_return(
          status: 200,
          body: [sample_place].to_json,
          headers: {"Content-Type" => "application/json"}
        )

      fill_in "Address", with: "100 Holliday"

      expect(page).to have_css(
        "[data-testid='address-search-message']",
        text: "No matching addresses found. You can still submit the address as you typed it."
      )
      expect(page).to have_no_css("[role='listbox']")

      sleep 1.2

      fill_in "Address", with: ""
      fill_in "Address", with: "100 Holliday"

      expect(page).to have_css("[role='option']", text: "100 Holliday St")
      expect(page).to have_no_css("[data-testid='address-search-message']")
    end
  end

  # @lat: [[lat.md/explanation/signup-address-search-browser-tests#Signup address search browser tests#Autocomplete endpoint failure]]
  it "displays an unavailable message when the autocomplete endpoint returns 500 and recovers" do
    stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
      .to_return(
        status: 200,
        body: [sample_place].to_json,
        headers: {"Content-Type" => "application/json"}
      )

    page.execute_script(<<~JS)
      const originalFetch = window.fetch;
      let failedOnce = false;
      window.fetch = function(...args) {
        const url = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url) || '';
        if (!failedOnce && url.includes('/addresses/autocomplete')) {
          failedOnce = true;
          return Promise.resolve(new Response(JSON.stringify({ error: 'Server Error' }), {
            status: 500,
            statusText: 'Internal Server Error',
            headers: { 'Content-Type': 'application/json' }
          }));
        }
        return originalFetch.apply(this, args);
      };
    JS

    fill_in "Address", with: "100 Holliday"

    expect(page).to have_css(
      "[data-testid='address-search-message']",
      text: "Address search is unavailable right now. You can still submit the address as you typed it."
    )
    expect(page).to have_no_css("[role='listbox']")

    fill_in "Address", with: "100 Holliday St"

    expect(page).to have_css("[role='option']", text: "100 Holliday St")
    expect(page).to have_no_css("[data-testid='address-search-message']")
  end

  # @lat: [[lat.md/explanation/signup-address-search-browser-tests#Signup address search browser tests#Bounded-locale miss]]
  it "retries without bounding box when a strict-box locale search yields no results" do
    baltimore = create(:sway_locale, :baltimore)
    visit "/sway_registration?sway_locale_id=#{baltimore.id}"
    wait_until_loaded
    expect(page).to have_field("Address")

    unbounded_stub = stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
      .with { |req| !req.uri.query.to_s.include?("bounded=1") }
      .to_return(
        status: 200,
        body: [towson_place].to_json,
        headers: {"Content-Type" => "application/json"}
      )

    bounded_stub = stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
      .with(query: hash_including("bounded" => "1"))
      .to_return(
        status: 200,
        body: [].to_json,
        headers: {"Content-Type" => "application/json"}
      )

    fill_in "Address", with: "Towson"

    expect(page).to have_css("[role='option']", text: "1 Allegheny Ave")
    expect(bounded_stub).to have_been_requested.once
    expect(unbounded_stub).to have_been_requested.once
  end

  # @lat: [[lat.md/explanation/signup-address-search-browser-tests#Signup address search browser tests#Edit after select]]
  it "drops selected address metadata when the user edits the input and posts the typed street" do
    stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
      .to_return(
        status: 200,
        body: [sample_place].to_json,
        headers: {"Content-Type" => "application/json"}
      )

    fill_in "Address", with: "100 Holliday"

    expect(page).to have_css("[role='option']", text: "100 Holliday St")
    find("[role='option']", text: "100 Holliday St").click

    address_input = find_field("Address")
    expect(address_input.value).to include("100 Holliday St")

    fill_in "Address", with: "999 Custom Street"

    expect(page).to have_css("[data-testid='btn-submit-registration']:not([disabled])")
    find("[data-testid='btn-submit-registration']:not([disabled])").click

    wait_until { user.reload.user_address.present? }

    user_addr = user.reload.user_address.address
    expect(user_addr.street).to eq("999 Custom Street")
    expect(user_addr.city).not_to eq("Baltimore")

    expect(page).to have_no_css("#address-error")
    expect(page).to have_no_css("dialog#inertia-error-dialog")
  end
end
