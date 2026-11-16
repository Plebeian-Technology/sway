# frozen_string_literal: true

require "rails_helper"

# @lat: [[signup-pending-vote-browser-tests#Signup pending-vote browser tests]]
RSpec.describe "Signup pending vote browser journey", type: :system, js: true do
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

  # @lat: [[signup-pending-vote-browser-tests#Provisional vote reconciliation]]
  it "records a provisional vote after completing registration" do
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

    bill = create(
      :bill,
      :bill_of_the_month,
      sway_locale: congress_locale,
      legislator: congress_rep,
      title: "Monthly Preview Test Bill"
    )

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

    visit "/bill_of_the_month"
    expect(page).to have_text(:visible, bill.title, wait: 20)

    @authenticator_id = enable_virtual_authenticator
    click_button("For", match: :first)

    modal = find("[data-testid='provisional-registration-modal']", visible: :visible, wait: 20)
    phone = "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"

    within(modal) do
      fill_in "Phone number", with: phone
      click_button "Continue with Phone"

      expect(page).to have_field("v2-code", wait: 10)
      fill_in "v2-code", with: "123456"
      click_button "Confirm code"
    end

    expect(page).to have_current_path(sway_registration_index_path, wait: 10)
    expect(page).to have_css("h1", text: "Complete your registration")

    fill_in "Address", with: "100 N Holliday"
    find("[role='option']", text: "100 N Holliday St", wait: 10).click

    find("[data-testid='btn-submit-registration']").click

    expect(page).to have_current_path(bill_path(bill), wait: 15)

    user = User.find_by!(phone: phone)
    expect(UserVote.where(user: user, bill: bill).pluck(:support)).to eq(["FOR"])
    expect(page).to have_css("[data-testid='vote-recorded']", wait: 10)

    pending_vote_cookie = page.driver.browser.manage.all_cookies.find do |cookie|
      (cookie[:name] || cookie["name"]) == "sway_pending_vote"
    end
    expect(pending_vote_cookie).to be_nil
  end
end
