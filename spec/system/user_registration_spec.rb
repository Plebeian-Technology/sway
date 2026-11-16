# frozen_string_literal: true

require "rails_helper"

RSpec.describe "User Registration", type: :system, js: true do
  include ActiveJob::TestHelper

  include_context "TwilioDouble"

  let(:phone) do
    "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"
  end

  # ---- Capybara host setup (the fake WebAuthn authenticator matches on origin) ----
  around do |example|
    initial_values = {} #: Hash[String, String?]
    # @lat: [[identity-and-access#Registration is asynchronous by necessity#OpenStates system stubs exercise the request boundary]]
    env_overrides = {
      "TWILIO_ACCOUNT_SID" => "test-sid",
      "TWILIO_AUTH_TOKEN" => "test-token",
      "OPEN_STATES_API_KEY" => "test-open-states-key"
    }
    previous_values =
      env_overrides.each_with_object(initial_values) do |(key, _value), memo|
        memo[key] = ENV.fetch(key, nil)
      end

    begin
      env_overrides.each { |key, value| ENV[key] = value }

      # This registration flow needs the REAL phone check to run -- the skip
      # switch on would short-circuit it. The server runs in a thread of this
      # same process, so the swapped setting is visible to it.
      with_app_config(:dev_login, skip_phone_verification: false) { example.run }
    ensure
      previous_values.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end
  end

  before do
    empty_array = [] #: Array[untyped]

    ActiveJob::Base.queue_adapter = :test
    # @lat: [[identity-and-access#Registration is asynchronous by necessity#OpenStates system stubs exercise the request boundary]]
    stub_request(:get, %r{v3\.openstates\.org/people\.geo})
      .to_return(
        status: 200,
        body: {results: empty_array}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
    visit root_path
    @active_authenticators = [enable_virtual_authenticator]
  end

  after do
    Array(@active_authenticators).reverse_each do |id|
      disable_virtual_authenticator(id)
    end
  end

  # The whole registration journey: phone, passkey, and address, all finished
  # inside the request.
  it "completes sync registration: phone verify, passkey create, address submit, redirect to legislators" do
    sway_locale =
      create(
        :sway_locale,
        city: "baltimore",
        state: "MD",
        country: "United States"
      )
    district = create(:district, name: "MD7", sway_locale: sway_locale)
    local_legislator = create(:legislator, district: district, active: true)
    seat = Seat.find_or_create_by_identity!(
      district: district,
      office_identity: "test-baltimore-district-7",
      title: "Test representative",
      chamber: "House"
    )
    # SwayRegistrationService#district_legislators now keeps only legislators
    # who are serving, which it works out from their terms; the old `active`
    # column is gone. Give this one a term so it counts as a match.
    create(:legislator_term, legislator: local_legislator, district: district, seat: seat)

    geocode_double = double("SwayGeocode::Local", districts: [0, 7])
    allow(SwayGeocode).to receive(:build).and_return(geocode_double)

    user = register_passkey_user(phone: phone)
    expect(user).to be_present
    expect(user.registration_status).to eq("pending")

    visit sway_registration_index_path

    # Post the address directly, skipping the Google Maps autocomplete UI.
    browser_json_request(
      "POST",
      "/sway_registration",
      {
        sway_registration: {
          street: "100 N Holliday St",
          city: "Baltimore",
          region_code: "MD",
          postal_code: "21202",
          country: "US",
          latitude: "39.29105",
          longitude: "-76.61069"
        }
      }
    )

    # The registration already finished synchronously during the POST above.
    visit sway_registration_index_path

    # @lat: [[identity-and-access#Registration is asynchronous by necessity]]
    expect(page).to have_current_path(
      /\/feed/,
      ignore_query: true,
      wait: 15
    )

    user.reload
    expect(user.registration_status).to eq("completed")
    expect(user.is_registration_complete).to eq(true)
    expect(UserLegislator.where(user: user).count).to be >= 1
  end

  # @lat: [[registration-dead-ends#An empty list says which kind of empty it is]]
  it "completes a user whose address resolves no representative, with the Congress locale waiting" do
    create(:sway_locale, city: "baltimore", state: "MD", country: "United States")
    allow(Sentry).to receive(:capture_message)
    user = register_passkey_user(phone: phone)

    visit sway_registration_index_path
    # @lat: [[registration-dead-ends#An empty list says which kind of empty it is#The browser example waits for the address form beacon]]
    wait_until do
      page.evaluate_script("performance.getEntriesByType('resource').some((entry) => entry.name.endsWith('/api/v1/funnel_events'))")
    end
    address_params = {
      sway_registration: {
        street: "100 N Holliday St",
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21202",
        country: "US",
        latitude: 39.29105,
        longitude: -76.61069
      }
    }
    outcome = page.driver.browser.execute_async_script(<<~JS, "/sway_registration", address_params)
      const path = arguments[0];
      const payload = arguments[1];
      const done = arguments[arguments.length - 1];
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || "";
      fetch(path, {
        method: "POST",
        credentials: "same-origin",
        redirect: "follow",
        headers: {
          "Accept": "text/html",
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "X-XSRF-Token": csrfToken
        },
        body: JSON.stringify(payload)
      }).then((response) => done({status: response.status, path: new URL(response.url).pathname}))
        .catch((error) => done({error: String(error)}));
    JS

    expect(outcome).not_to have_key("error")
    expect(outcome).to include("path" => feed_path)
    visit sway_registration_index_path

    expect(page).to have_current_path(feed_path, ignore_query: true, wait: 15)
    user.reload
    expect(user.registration_status).to eq("completed")
    expect(user.is_registration_complete).to be(true)
    expect(user.pending_representative_locale_ids).to eq([SwayLocale.default_locale&.id])
    expect(UserLegislator.where(user: user, active: true)).to be_empty
    expect(Sentry).to have_received(:capture_message).with(
      "sway_registration.no_representatives_resolved",
      level: :warning,
      extra: hash_including(user_id: user.id)
    )
  end

  # A user who already registered goes straight to the legislators page.
  it "redirects already-registered user to legislators without re-processing" do
    sway_locale =
      create(
        :sway_locale,
        city: "baltimore",
        state: "MD",
        country: "United States"
      )
    district = create(:district, name: "MD7", sway_locale: sway_locale)
    legislator = create(:legislator, district: district, active: true)
    create(:legislator_term, legislator: legislator, district: district)

    # Stub geocoding: not expected to be called, but a safe default.
    geocode_double = double("SwayGeocode::Local", districts: [0, 7])
    allow(SwayGeocode).to receive(:build).and_return(geocode_double)

    user = register_passkey_user(phone: phone)

    create(:user_legislator, user: user, legislator: legislator)
    user.complete!

    # Clear jobs left over from setup; register_passkey_user can queue some.
    queue_adapter.enqueued_jobs.clear

    visit sway_registration_index_path
    expect(page).to have_current_path(
      /\/feed/,
      ignore_query: true,
      wait: 10
    )

    # The redirect must not have queued any new jobs.
    expect(enqueued_jobs.size).to eq(0)
  end
end
