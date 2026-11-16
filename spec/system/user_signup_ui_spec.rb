# frozen_string_literal: true

require "rails_helper"

RSpec.describe "User sign-up browser journeys", type: :system, js: true do
  include_context "TwilioDouble"

  let!(:baltimore_locale) { create(:sway_locale, :baltimore) }
  let!(:maryland_locale) { create(:sway_locale, :maryland) }
  let!(:congress_locale) { create(:sway_locale, :congress) }

  around do |example|
    initial_values = {} #: Hash[String, String?]
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
      with_app_config(:dev_login, skip_phone_verification: false) { example.run }
    ensure
      previous_values.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end
  end

  before do
    ActiveJob::Base.queue_adapter = :test
  end

  after do
    disable_virtual_authenticator(@authenticator_id) if @authenticator_id
  end

  # @lat: [[signup-browser-journeys#Web sign-up browser journeys#Baltimore City sign-up journey#Municipal representative is matched and visible]]
  it "drives a Baltimore user through registration to visible municipal representation" do
    baltimore_address = Address.new(latitude: 39.29105, longitude: -76.61069)
    district_number = SwayGeocode::Local.new(baltimore_locale, baltimore_address).districts.last
    baltimore_district = create(:district, name: "MD#{district_number}", sway_locale: baltimore_locale)
    baltimore_rep = create(:legislator, district: baltimore_district, sway_locale: baltimore_locale, active: true)
    baltimore_seat = Seat.find_or_create_by_identity!(
      district: baltimore_district,
      office_identity: "baltimore-district-#{district_number}",
      title: "Test representative",
      chamber: "House"
    )
    create(:legislator_term, legislator: baltimore_rep, district: baltimore_district, seat: baltimore_seat)

    congress_district = create(:district, name: "MD7", sway_locale: congress_locale)
    congress_rep = create(:legislator, district: congress_district, sway_locale: congress_locale, active: true)
    congress_seat = Seat.find_or_create_by_identity!(
      district: congress_district,
      office_identity: "congress-district-md7",
      title: "Rep.",
      chamber: "House of Representatives"
    )
    create(:legislator_term, legislator: congress_rep, district: congress_district, seat: congress_seat, title: "Rep.")

    stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: [
          {
            place_id: "1001",
            lat: "39.29105",
            lon: "-76.61069",
            display_name: "100 N Holliday St, Baltimore, Maryland, 21202, United States",
            address: {
              :house_number => "100",
              :road => "N Holliday St",
              :city => "Baltimore",
              :state => "Maryland",
              :postcode => "21202",
              :country => "United States",
              :country_code => "us",
              "ISO3166-2-lvl4" => "US-MD"
            }
          }
        ].to_json
      )

    stub_request(:get, %r{tigerweb\.geo\.census\.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2024/MapServer/54/query})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: {
          features: [
            {attributes: {"STATE" => "24", "CD119" => "07"}}
          ]
        }.to_json
      )

    stub_request(:get, %r{v3\.openstates\.org/people\.geo})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: {results: []}.to_json
      )

    phone = generate_phone_number
    drive_signup_journey(
      phone: phone,
      address_query: "100 N Holliday",
      option_text: "100 N Holliday St"
    )

    user = User.find_by!(phone: phone)
    expect(user.registration_status).to eq("completed")
    expect(user.is_registration_complete).to be(true)
    expect(UserAddress.where(user: user).count).to eq(1)
    expect(UserLegislator.where(user: user, legislator: baltimore_rep, active: true)).to exist

    visit "/legislators?sway_locale_id=#{baltimore_locale.id}"
    app = find_by_id("app", wait: 10)
    expect(app).to have_text(baltimore_rep.full_name)
    expect(app).to have_link("View representative", href: "/legislators/#{baltimore_rep.id}")
  end

  # @lat: [[signup-browser-journeys#Web sign-up browser journeys#Maryland state sign-up journey#State representative is matched and visible]]
  it "drives a Maryland user through registration to visible state representation" do
    md_district = create(:district, name: "MD42", sway_locale: maryland_locale)
    md_rep = create(
      :legislator,
      district: md_district,
      sway_locale: maryland_locale,
      external_id: "MD-LEG-42",
      active: true
    )
    md_seat = Seat.find_or_create_by_identity!(
      district: md_district,
      office_identity: "maryland-district-42",
      title: "Delegate",
      chamber: "House of Delegates"
    )
    create(
      :legislator_term,
      legislator: md_rep,
      district: md_district,
      seat: md_seat,
      title: "Delegate"
    )

    congress_district = create(:district, name: "MD2", sway_locale: congress_locale)
    congress_rep = create(:legislator, district: congress_district, sway_locale: congress_locale, active: true)
    congress_seat = Seat.find_or_create_by_identity!(
      district: congress_district,
      office_identity: "congress-district-md2",
      title: "Rep.",
      chamber: "House of Representatives"
    )
    create(
      :legislator_term,
      legislator: congress_rep,
      district: congress_district,
      seat: congress_seat,
      title: "Rep."
    )

    stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: [
          {
            place_id: "2001",
            lat: "39.4015",
            lon: "-76.6019",
            display_name: "400 Washington Ave, Towson, Maryland, 21204, United States",
            address: {
              :house_number => "400",
              :road => "Washington Ave",
              :city => "Towson",
              :state => "Maryland",
              :postcode => "21204",
              :country => "United States",
              :country_code => "us",
              "ISO3166-2-lvl4" => "US-MD"
            }
          }
        ].to_json
      )

    stub_request(:get, %r{tigerweb\.geo\.census\.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2024/MapServer/54/query})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: {
          features: [
            {attributes: {"STATE" => "24", "CD119" => "02"}}
          ]
        }.to_json
      )

    stub_request(:get, %r{v3\.openstates\.org/people\.geo})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: {
          results: [
            {id: md_rep.external_id, jurisdiction: {name: "Maryland"}}
          ]
        }.to_json
      )

    phone = generate_phone_number
    drive_signup_journey(
      phone: phone,
      address_query: "400 Washington Ave",
      option_text: "400 Washington Ave"
    )

    user = User.find_by!(phone: phone)
    expect(user.registration_status).to eq("completed")
    expect(user.is_registration_complete).to be(true)
    expect(UserAddress.where(user: user).count).to eq(1)
    expect(UserLegislator.where(user: user, legislator: md_rep, active: true)).to exist

    visit "/legislators?sway_locale_id=#{maryland_locale.id}"
    app = find_by_id("app", wait: 10)
    expect(app).to have_text(md_rep.full_name)
    expect(app).to have_link("View representative", href: "/legislators/#{md_rep.id}")
  end

  # @lat: [[signup-browser-journeys#Web sign-up browser journeys#Congressional sign-up journey#Congressional representative is matched and visible]]
  it "drives an out-of-state user through registration to visible congressional representation" do
    congress_district = create(:district, name: "VA4", sway_locale: congress_locale)
    congress_rep = create(:legislator, district: congress_district, sway_locale: congress_locale, active: true)
    congress_seat = Seat.find_or_create_by_identity!(
      district: congress_district,
      office_identity: "congress-district-va4",
      title: "Rep.",
      chamber: "House of Representatives"
    )
    create(
      :legislator_term,
      legislator: congress_rep,
      district: congress_district,
      seat: congress_seat,
      title: "Rep."
    )

    stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: [
          {
            place_id: "3001",
            lat: "37.5407",
            lon: "-77.4360",
            display_name: "1000 E Broad St, Richmond, Virginia, 23219, United States",
            address: {
              :house_number => "1000",
              :road => "E Broad St",
              :city => "Richmond",
              :state => "Virginia",
              :postcode => "23219",
              :country => "United States",
              :country_code => "us",
              "ISO3166-2-lvl4" => "US-VA"
            }
          }
        ].to_json
      )

    stub_request(:get, %r{tigerweb\.geo\.census\.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2024/MapServer/54/query})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: {
          features: [
            {attributes: {"STATE" => "51", "CD119" => "04"}}
          ]
        }.to_json
      )

    stub_request(:get, %r{v3\.openstates\.org/people\.geo})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: {results: []}.to_json
      )

    phone = generate_phone_number
    drive_signup_journey(
      phone: phone,
      address_query: "1000 E Broad",
      option_text: "1000 E Broad St"
    )

    user = User.find_by!(phone: phone)
    expect(user.registration_status).to eq("completed")
    expect(user.is_registration_complete).to be(true)
    expect(UserAddress.where(user: user).count).to eq(1)
    expect(UserLegislator.where(user: user, legislator: congress_rep, active: true)).to exist

    visit "/legislators?sway_locale_id=#{congress_locale.id}"
    app = find_by_id("app", wait: 10)
    expect(app).to have_text(congress_rep.full_name)
    expect(app).to have_link("View representative", href: "/legislators/#{congress_rep.id}")
  end

  # @lat: [[signup-browser-journeys#Web sign-up browser journeys#Annapolis sign-up journey#City, state, and federal representatives are matched and visible]]
  it "drives an Annapolis user through registration to visible municipal, state, and congressional representation" do
    annapolis_locale = create(:sway_locale, city: "annapolis", state: "maryland", country: "united_states")
    annapolis_d0 = create(:district, name: "MD0", sway_locale: annapolis_locale)
    annapolis_mayor = create(
      :legislator,
      district: annapolis_d0,
      sway_locale: annapolis_locale,
      first_name: "Gavin",
      last_name: "Buckley",
      title: "Mayor",
      external_id: "annapolis-mayor",
      active: true
    )
    annapolis_mayor_seat = Seat.find_or_create_by_identity!(
      district: annapolis_d0,
      office_identity: "annapolis-mayor",
      title: "Mayor",
      chamber: "Executive"
    )
    create(
      :legislator_term,
      legislator: annapolis_mayor,
      district: annapolis_d0,
      seat: annapolis_mayor_seat,
      title: "Mayor"
    )

    annapolis_d1 = create(:district, name: "MD1", sway_locale: annapolis_locale)
    annapolis_rep = create(
      :legislator,
      district: annapolis_d1,
      sway_locale: annapolis_locale,
      first_name: "Elly",
      last_name: "Tierney",
      title: "Alderperson",
      external_id: "annapolis-ward-1",
      active: true
    )
    annapolis_rep_seat = Seat.find_or_create_by_identity!(
      district: annapolis_d1,
      office_identity: "annapolis-ward-1",
      title: "Alderperson",
      chamber: "City Council"
    )
    create(
      :legislator_term,
      legislator: annapolis_rep,
      district: annapolis_d1,
      seat: annapolis_rep_seat,
      title: "Alderperson"
    )

    md_district = create(:district, name: "MD30", sway_locale: maryland_locale)
    md_rep = create(
      :legislator,
      district: md_district,
      sway_locale: maryland_locale,
      external_id: "MD-LEG-30",
      active: true
    )
    md_seat = Seat.find_or_create_by_identity!(
      district: md_district,
      office_identity: "maryland-district-30",
      title: "Delegate",
      chamber: "House of Delegates"
    )
    create(
      :legislator_term,
      legislator: md_rep,
      district: md_district,
      seat: md_seat,
      title: "Delegate"
    )

    congress_district = create(:district, name: "MD3", sway_locale: congress_locale)
    congress_rep = create(:legislator, district: congress_district, sway_locale: congress_locale, active: true)
    congress_seat = Seat.find_or_create_by_identity!(
      district: congress_district,
      office_identity: "congress-district-md3",
      title: "Rep.",
      chamber: "House of Representatives"
    )
    create(
      :legislator_term,
      legislator: congress_rep,
      district: congress_district,
      seat: congress_seat,
      title: "Rep."
    )

    stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: [
          {
            place_id: "4001",
            lat: "38.9784",
            lon: "-76.4922",
            display_name: "160 Duke of Gloucester St, Annapolis, Maryland, 21401, United States",
            address: {
              :house_number => "160",
              :road => "Duke of Gloucester St",
              :city => "Annapolis",
              :state => "Maryland",
              :postcode => "21401",
              :country => "United States",
              :country_code => "us",
              "ISO3166-2-lvl4" => "US-MD"
            }
          }
        ].to_json
      )

    stub_request(:get, %r{tigerweb\.geo\.census\.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2024/MapServer/54/query})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: {
          features: [
            {attributes: {"STATE" => "24", "CD119" => "03"}}
          ]
        }.to_json
      )

    stub_request(:get, %r{v3\.openstates\.org/people\.geo})
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: {
          results: [
            {id: md_rep.external_id, jurisdiction: {name: "Maryland"}}
          ]
        }.to_json
      )

    phone = generate_phone_number
    drive_signup_journey(
      phone: phone,
      address_query: "160 Duke of Gloucester",
      option_text: "160 Duke of Gloucester St"
    )

    user = User.find_by!(phone: phone)
    expect(user.registration_status).to eq("completed")
    expect(user.is_registration_complete).to be(true)
    expect(UserAddress.where(user: user).count).to eq(1)
    expect(UserLegislator.where(user: user, legislator: annapolis_mayor, active: true)).to exist
    expect(UserLegislator.where(user: user, legislator: annapolis_rep, active: true)).to exist
    expect(UserLegislator.where(user: user, legislator: md_rep, active: true)).to exist
    expect(UserLegislator.where(user: user, legislator: congress_rep, active: true)).to exist

    visit "/legislators?sway_locale_id=#{annapolis_locale.id}"
    app = find_by_id("app", wait: 10)
    expect(app).to have_text(annapolis_mayor.full_name)
    expect(app).to have_link("View representative", href: "/legislators/#{annapolis_mayor.id}")
    expect(app).to have_text(annapolis_rep.full_name)
    expect(app).to have_link("View representative", href: "/legislators/#{annapolis_rep.id}")

    visit "/legislators?sway_locale_id=#{maryland_locale.id}"
    app = find_by_id("app", wait: 10)
    expect(app).to have_text(md_rep.full_name)
    expect(app).to have_link("View representative", href: "/legislators/#{md_rep.id}")

    visit "/legislators?sway_locale_id=#{congress_locale.id}"
    app = find_by_id("app", wait: 10)
    expect(app).to have_text(congress_rep.full_name)
    expect(app).to have_link("View representative", href: "/legislators/#{congress_rep.id}")
  end

  def generate_phone_number
    "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"
  end

  def drive_signup_journey(phone:, address_query:, option_text:)
    visit root_path
    expect(page).to have_button("Continue with Phone", disabled: false, wait: 10)
    expect(page).to have_no_css("#application-loading")
    wait_until do
      page.evaluate_script(
        "performance.getEntriesByType('resource').some((entry) => entry.name.endsWith('/api/v1/funnel_events'))"
      )
    end
    @authenticator_id = enable_virtual_authenticator

    fill_in "Phone number", with: phone
    click_button "Continue with Phone"

    expect(page).to have_field("v2-code", wait: 10)
    fill_in "v2-code", with: "123456"
    click_button "Confirm code"

    expect(page).to have_current_path(sway_registration_index_path, wait: 20)
    expect(page).to have_css("h1", text: "Complete your registration")

    fill_in "Address", with: address_query
    find("[role='option']", text: option_text, wait: 10).click

    find("[data-testid='btn-submit-registration']").click
    expect(page).to have_current_path(feed_path, ignore_query: true, wait: 20)
  end
end
