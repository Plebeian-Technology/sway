# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Signup registration failures", type: :system, js: true do
  let(:pending_user) { create(:user, is_registration_complete: false, registration_status: "pending") }
  let(:congress_locale) { create(:sway_locale, :congress) }
  let(:baltimore_locale) { create(:sway_locale, :baltimore) }
  let(:maryland_locale) { create(:sway_locale, :maryland) }

  around do |example|
    with_env(
      "GOOGLE_MAPS_API_KEY" => nil,
      "OPEN_STATES_API_KEY" => "test-open-states-key"
    ) do
      example.run
    end
  end

  before do
    allow(Sentry).to receive(:capture_exception)
    allow(Sentry).to receive(:capture_message)
  end

  # @lat: [[signup-registration-failure-browser-tests#Submit without a selection]]
  it "prompts for city or ZIP when typed address cannot be located and allows continuing to feed" do
    potus = create_potus_term(congress_locale)
    allow(Geocoder).to receive(:search).and_return([])
    stub_reg_fail_nominatim([])

    sign_in_as(pending_user)
    visit sway_registration_index_path
    wait_until_loaded
    wait_for_address_form_beacon

    fill_in "Address", with: "100 N Holliday"
    click_testid("btn-submit-registration")

    expect(page).to have_css(
      "[data-testid='address-not-located-message']",
      text: SwayRegistrationController::ADDRESS_NOT_LOCATED_MESSAGE
    )
    expect(page).to have_css("[data-testid='link-continue-to-feed']")
    expect(page).to have_no_css("dialog#inertia-error-dialog")
    expect(page).to have_no_css("[data-testid='confirm-address-switch-dialog']")

    pending_user.reload
    expect(pending_user.registration_status).to eq("completed")
    expect(pending_user.is_registration_complete).to be(true)
    expect(Address.count).to eq(1)

    created_address = pending_user.address
    expect(created_address.street).to eq("100 N Holliday")
    expect(created_address.latitude).to be_nil
    expect(created_address.longitude).to be_nil

    active_reps = pending_user.user_legislators.where(active: true).map(&:legislator)
    expect(active_reps).to contain_exactly(potus)
    expect(pending_user.pending_representative_locale_ids).to include(congress_locale.id)

    click_testid("link-continue-to-feed")
    expect(page).to have_current_path(feed_path, ignore_query: true, wait: 15)
  end

  describe "Census outage" do
    # @lat: [[signup-registration-failure-browser-tests#Census outage#HTTP 502 gateway error]]
    it "completes registration with state senators when Census returns an HTML 502" do
      baltimore_rep, md_rep, senators, house_rep = setup_census_outage_fixture(baltimore_locale, maryland_locale, congress_locale)
      drive_census_outage_journey(pending_user, status: 502, body: "<html><body>502 Bad Gateway</body></html>")
      assert_census_delegation(baltimore_locale, maryland_locale, congress_locale, baltimore_rep, md_rep, senators, house_rep)
    end

    # @lat: [[signup-registration-failure-browser-tests#Census outage#Empty body response]]
    it "completes registration with state senators when Census returns an empty 200 body" do
      baltimore_rep, md_rep, senators, house_rep = setup_census_outage_fixture(baltimore_locale, maryland_locale, congress_locale)
      drive_census_outage_journey(pending_user, status: 200, body: "")
      assert_census_delegation(baltimore_locale, maryland_locale, congress_locale, baltimore_rep, md_rep, senators, house_rep)
    end

    # @lat: [[signup-registration-failure-browser-tests#Census outage#Error JSON payload]]
    it "completes registration with state senators when Census returns an error JSON payload" do
      baltimore_rep, md_rep, senators, house_rep = setup_census_outage_fixture(baltimore_locale, maryland_locale, congress_locale)
      drive_census_outage_journey(
        pending_user,
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: {error: {code: 500, message: "ArcGIS Error"}}.to_json
      )
      assert_census_delegation(baltimore_locale, maryland_locale, congress_locale, baltimore_rep, md_rep, senators, house_rep)
    end
  end

  # @lat: [[signup-registration-failure-browser-tests#Unresolvable seat]]
  it "skips an unseated locale-wide term and completes registration with seated representatives" do
    baltimore_rep = setup_reg_baltimore_rep(baltimore_locale)
    md0 = District.find_or_create_by!(sway_locale: baltimore_locale, name: "MD0")
    mayor = create_reg_failure_term(
      district: md0,
      office_identity: "baltimore-mayor",
      title: "Mayor",
      chamber: "Executive",
      last_name: "Mayor"
    )
    unseated_officer = create(:legislator, district: md0, sway_locale: baltimore_locale, active: true, last_name: "Unseated")
    create(:legislator_term, legislator: unseated_officer, district: md0, seat: nil, title: "Mayor", term_start_year: 2024, term_end_year: 2028)

    stub_reg_fail_nominatim([baltimore_place_fixture])
    stub_reg_fail_open_states_empty
    stub_reg_fail_census_cd("07")

    sign_in_as(pending_user)
    visit sway_registration_index_path
    wait_until_loaded
    wait_for_address_form_beacon

    fill_in "Address", with: "100 N Holliday"
    find("[role='option']", text: "100 N Holliday St", wait: 10).click
    click_testid("btn-submit-registration")

    expect(page).to have_current_path(feed_path, ignore_query: true, wait: 20)
    expect(pending_user.reload.registration_status).to eq("completed")

    visit "/legislators?sway_locale_id=#{baltimore_locale.id}"
    wait_until_loaded
    expect(page).to have_link("View representative", href: "/legislators/#{mayor.id}")
    expect(page).to have_link("View representative", href: "/legislators/#{baltimore_rep.id}")
    expect(page).to have_no_css("a[href='/legislators/#{unseated_officer.id}']")
    expect(page).to have_no_css("dialog#inertia-error-dialog")
  end

  # @lat: [[signup-registration-failure-browser-tests#Address with no supported Sway locale]]
  it "completes registration with Virginia senators and district representative in Congress" do
    va0 = District.find_or_create_by!(sway_locale: congress_locale, name: "VA0")
    senator_1 = create_reg_failure_term(
      district: va0,
      office_identity: "va-senate-class-1",
      title: "United States Senator",
      chamber: "Senate",
      last_name: "Warner"
    )
    senator_2 = create_reg_failure_term(
      district: va0,
      office_identity: "va-senate-class-2",
      title: "United States Senator",
      chamber: "Senate",
      last_name: "Kaine"
    )
    va4 = District.find_or_create_by!(sway_locale: congress_locale, name: "VA4")
    rep_va = create_reg_failure_term(
      district: va4,
      office_identity: "congress-district-va4",
      title: "Rep.",
      chamber: "House of Representatives",
      last_name: "McClellan"
    )

    stub_reg_fail_nominatim([richmond_place_fixture])
    stub_reg_fail_census_cd("04", state: "51")

    sign_in_as(pending_user)
    visit sway_registration_index_path
    wait_until_loaded
    wait_for_address_form_beacon

    fill_in "Address", with: "1000 E Broad St"
    find("[role='option']", text: "1000 E Broad St", wait: 10).click
    click_testid("btn-submit-registration")

    expect(page).to have_current_path(feed_path, ignore_query: true, wait: 20)
    expect(pending_user.reload.registration_status).to eq("completed")

    visit "/legislators?sway_locale_id=#{congress_locale.id}"
    wait_until_loaded
    expect(page).to have_link("View representative", href: "/legislators/#{senator_1.id}")
    expect(page).to have_link("View representative", href: "/legislators/#{senator_2.id}")
    expect(page).to have_link("View representative", href: "/legislators/#{rep_va.id}")
    expect(page).to have_no_css("[data-testid='no-representatives-message']")
    expect(page).to have_no_text(SwayRegistrationController::REGISTRATION_NO_REPRESENTATIVES_MESSAGE)
  end

  # @lat: [[signup-registration-failure-browser-tests#Non-US address]]
  it "completes registration with the President as the sole representative for international addresses" do
    potus = create_potus_term(congress_locale)
    stub_reg_fail_nominatim([toronto_place_fixture])

    sign_in_as(pending_user)
    visit sway_registration_index_path
    wait_until_loaded
    wait_for_address_form_beacon

    fill_in "Address", with: "100 Queen St W"
    find("[role='option']", text: "100 Queen St W", wait: 10).click
    click_testid("btn-submit-registration")

    expect(page).to have_current_path(feed_path, ignore_query: true, wait: 20)
    expect(pending_user.reload.registration_status).to eq("completed")

    visit "/legislators?sway_locale_id=#{congress_locale.id}"
    wait_until_loaded
    expect(page).to have_link("View representative", href: "/legislators/#{potus.id}")
    expect(page).to have_css("a[href^='/legislators/']", count: 1)
  end

  # @lat: [[signup-registration-failure-browser-tests#Generic request failure]]
  it "displays an error notification and preserves the form when a network failure occurs" do
    stub_reg_fail_nominatim([baltimore_place_fixture])

    sign_in_as(pending_user)
    visit sway_registration_index_path
    wait_until_loaded
    wait_for_address_form_beacon

    fill_in "Address", with: "100 N Holliday"
    find("[role='option']", text: "100 N Holliday St", wait: 10).click

    page.execute_script(<<~JS)
      const origOpen = XMLHttpRequest.prototype.open;
      const origSend = XMLHttpRequest.prototype.send;
      let failedOnce = false;
      XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        this._requestUrl = typeof url === 'string' ? url : (url && url.toString()) || '';
        return origOpen.call(this, method, url, ...rest);
      };
      XMLHttpRequest.prototype.send = function(...args) {
        if (!failedOnce && this._requestUrl && this._requestUrl.includes('/sway_registration')) {
          failedOnce = true;
          setTimeout(() => {
            if (typeof this.onerror === 'function') {
              this.onerror(new ProgressEvent('error'));
            }
            this.dispatchEvent(new ProgressEvent('error'));
          }, 0);
          return;
        }
        return origSend.apply(this, args);
      };
    JS

    click_testid("btn-submit-registration")

    expect(page).to have_text("Something went wrong sending your address. Please try again.")
    expect(page).to have_field("Address")
    expect(page).to have_css("[data-testid='btn-submit-registration']")
    expect(page).to have_current_path(sway_registration_index_path, ignore_query: true)
  end

  # @lat: [[signup-registration-failure-browser-tests#Double submit]]
  it "handles double submissions cleanly creating one address and no duplicate representatives" do
    baltimore_rep = setup_reg_baltimore_rep(baltimore_locale)
    stub_reg_fail_nominatim([baltimore_place_fixture])
    stub_reg_fail_open_states_empty
    stub_reg_fail_census_cd("07")

    sign_in_as(pending_user)
    visit sway_registration_index_path
    wait_until_loaded
    wait_for_address_form_beacon

    fill_in "Address", with: "100 N Holliday"
    find("[role='option']", text: "100 N Holliday St", wait: 10).click

    page.execute_script(<<~JS)
      const btn = document.querySelector("[data-testid='btn-submit-registration']");
      const form = btn.closest('form');
      form.requestSubmit();
      form.requestSubmit();
    JS

    expect(page).to have_current_path(feed_path, ignore_query: true, wait: 20)
    expect(page).to have_no_text("Something went wrong sending your address")
    expect(UserAddress.where(user: pending_user).count).to eq(1)

    assigned_legislator_ids = UserLegislator.where(user: pending_user).pluck(:legislator_id)
    expect(assigned_legislator_ids).to eq(assigned_legislator_ids.uniq)
    expect(assigned_legislator_ids).to include(baltimore_rep.id)
  end

  # @lat: [[signup-registration-failure-browser-tests#Expired session]]
  it "redirects an unauthenticated client to the landing page with authentication prompts" do
    stub_reg_fail_nominatim([baltimore_place_fixture])

    sign_in_as(pending_user)
    visit sway_registration_index_path
    wait_until_loaded
    wait_for_address_form_beacon

    fill_in "Address", with: "100 N Holliday"
    find("[role='option']", text: "100 N Holliday St", wait: 10).click

    page.driver.browser.manage.delete_all_cookies
    click_testid("btn-submit-registration")

    expect(page).to have_current_path(root_path, ignore_query: true, wait: 20)
    expect(page).to have_text("Continue with Phone")
    expect(page).to have_no_css("dialog#inertia-error-dialog")
  end

  def create_potus_term(congress)
    us0 = District.find_or_create_by!(sway_locale: congress, name: "US0")
    potus_seat = Seat.find_or_create_by_identity!(
      district: us0,
      office_identity: RepresentativeReassignmentObserver::PRESIDENT_SEAT_IDENTIFIER,
      title: "President",
      chamber: "Executive"
    )
    potus = create(:legislator, district: us0, sway_locale: congress, active: true)
    create(
      :legislator_term,
      legislator: potus,
      district: us0,
      seat: potus_seat,
      title: "President",
      term_start_year: 2025,
      term_end_year: 2029
    )
    potus
  end

  def create_reg_failure_term(district:, office_identity:, title:, chamber:, last_name: nil, external_id: nil)
    seat = Seat.find_or_create_by_identity!(
      district:,
      office_identity:,
      title:,
      chamber:
    )
    legislator_attrs = {district:, sway_locale: district.sway_locale, active: true} #: Hash[Symbol, untyped]
    legislator_attrs[:last_name] = last_name if last_name
    legislator_attrs[:external_id] = external_id if external_id
    legislator = create(:legislator, **legislator_attrs)
    create(
      :legislator_term,
      legislator:,
      district:,
      seat:,
      title:,
      term_start_year: 2025,
      term_end_year: 2027
    )
    legislator
  end

  def setup_reg_baltimore_rep(baltimore)
    baltimore_address = Address.new(latitude: 39.29105, longitude: -76.61069)
    district_number = SwayGeocode::Local.new(baltimore, baltimore_address).districts.last
    baltimore_district = District.find_or_create_by!(name: "MD#{district_number}", sway_locale: baltimore)
    create_reg_failure_term(
      district: baltimore_district,
      office_identity: "baltimore-district-#{district_number}",
      title: "Councilmember",
      chamber: "City Council",
      last_name: "CityRep"
    )
  end

  def setup_reg_maryland_rep(maryland)
    md_district = District.find_or_create_by!(name: "MD46", sway_locale: maryland)
    create_reg_failure_term(
      district: md_district,
      office_identity: "maryland-district-46",
      title: "Delegate",
      chamber: "House of Delegates",
      last_name: "StateRep",
      external_id: "MD-LEG-46"
    )
  end

  def setup_reg_maryland_senators(congress)
    md0 = District.find_or_create_by!(sway_locale: congress, name: "MD0")
    senator_a = create_reg_failure_term(
      district: md0,
      office_identity: "md-senate-class-1",
      title: "United States Senator",
      chamber: "Senate",
      last_name: "SenatorA"
    )
    senator_b = create_reg_failure_term(
      district: md0,
      office_identity: "md-senate-class-3",
      title: "United States Senator",
      chamber: "Senate",
      last_name: "SenatorB"
    )
    [senator_a, senator_b]
  end

  def setup_reg_congress_rep(congress, district_name:)
    congress_district = District.find_or_create_by!(sway_locale: congress, name: district_name)
    create_reg_failure_term(
      district: congress_district,
      office_identity: "congress-district-#{district_name.downcase}",
      title: "Rep.",
      chamber: "House of Representatives",
      last_name: "HouseRep"
    )
  end

  def setup_census_outage_fixture(baltimore, maryland, congress)
    baltimore_rep = setup_reg_baltimore_rep(baltimore)
    md_rep = setup_reg_maryland_rep(maryland)
    maryland_senators = setup_reg_maryland_senators(congress)
    house_rep = setup_reg_congress_rep(congress, district_name: "MD7")
    stub_reg_fail_nominatim([baltimore_place_fixture])
    stub_reg_fail_open_states_rep(md_rep)
    [baltimore_rep, md_rep, maryland_senators, house_rep]
  end

  def drive_census_outage_journey(user, status:, body: nil, headers: {})
    stub_reg_fail_census_outage(status:, body:, headers:)

    sign_in_as(user)
    visit sway_registration_index_path
    wait_until_loaded
    wait_for_address_form_beacon

    fill_in "Address", with: "100 N Holliday"
    find("[role='option']", text: "100 N Holliday St", wait: 10).click
    click_testid("btn-submit-registration")

    expect(page).to have_current_path(feed_path, ignore_query: true, wait: 20)
    expect(page).to have_no_text(SwayRegistrationController::REGISTRATION_UNAVAILABLE_MESSAGE)
    expect(user.reload.registration_status).to eq("completed")
  end

  def assert_census_delegation(baltimore, maryland, congress, baltimore_rep, md_rep, senators, house_rep)
    senator_a, senator_b = senators

    visit "/legislators?sway_locale_id=#{baltimore.id}"
    wait_until_loaded
    expect(page).to have_link("View representative", href: "/legislators/#{baltimore_rep.id}")

    visit "/legislators?sway_locale_id=#{maryland.id}"
    wait_until_loaded
    expect(page).to have_link("View representative", href: "/legislators/#{md_rep.id}")

    visit "/legislators?sway_locale_id=#{congress.id}"
    wait_until_loaded
    expect(page).to have_link("View representative", href: "/legislators/#{senator_a.id}")
    expect(page).to have_link("View representative", href: "/legislators/#{senator_b.id}")
    expect(page).to have_no_css("a[href='/legislators/#{house_rep.id}']")
  end

  def wait_for_address_form_beacon
    wait_until do
      page.evaluate_script(
        "performance.getEntriesByType('resource').some((entry) => entry.name.endsWith('/api/v1/funnel_events'))"
      )
    end
  end

  def baltimore_place_fixture
    {
      "place_id" => 1001,
      "lat" => "39.29105",
      "lon" => "-76.61069",
      "display_name" => "100 N Holliday St, Baltimore, Maryland, 21202, United States",
      "address" => {
        "house_number" => "100",
        "road" => "N Holliday St",
        "city" => "Baltimore",
        "state" => "Maryland",
        "postcode" => "21202",
        "country" => "United States",
        "country_code" => "us",
        "ISO3166-2-lvl4" => "US-MD"
      }
    }
  end

  def richmond_place_fixture
    {
      "place_id" => 1002,
      "lat" => "37.5407",
      "lon" => "-77.4360",
      "display_name" => "1000 E Broad St, Richmond, Virginia, 23219, United States",
      "address" => {
        "house_number" => "1000",
        "road" => "E Broad St",
        "city" => "Richmond",
        "state" => "Virginia",
        "postcode" => "23219",
        "country" => "United States",
        "country_code" => "us",
        "ISO3166-2-lvl4" => "US-VA"
      }
    }
  end

  def toronto_place_fixture
    {
      "place_id" => 1003,
      "lat" => "43.6532",
      "lon" => "-79.3832",
      "display_name" => "100 Queen St W, Toronto, Ontario, M5H 2N2, Canada",
      "address" => {
        "house_number" => "100",
        "road" => "Queen St W",
        "city" => "Toronto",
        "state" => "Ontario",
        "postcode" => "M5H 2N2",
        "country" => "Canada",
        "country_code" => "ca"
      }
    }
  end

  def stub_reg_fail_nominatim(results)
    stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: results.to_json
      )
  end

  def stub_reg_fail_census_outage(status:, body: nil, headers: {})
    stub_request(:get, %r{tigerweb\.geo\.census\.gov/arcgis/rest/services/TIGERweb/})
      .to_return(status:, headers:, body:)
  end

  def stub_reg_fail_census_cd(district_number, state: "24")
    stub_request(:get, %r{tigerweb\.geo\.census\.gov/arcgis/rest/services/TIGERweb/})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: {
          features: [
            {attributes: {"STATE" => state, "CD119" => district_number}}
          ]
        }.to_json
      )
  end

  def stub_reg_fail_open_states_empty
    stub_request(:get, %r{v3\.openstates\.org/people\.geo})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: {results: []}.to_json
      )
  end

  def stub_reg_fail_open_states_rep(rep)
    stub_request(:get, %r{v3\.openstates\.org/people\.geo})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: {
          results: [
            {id: rep.external_id, jurisdiction: {name: "Maryland"}}
          ]
        }.to_json
      )
  end
end
