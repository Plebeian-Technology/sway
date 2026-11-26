# frozen_string_literal: true

require "rails_helper"

# @lat: [[web-profile-page#Web profile page#Changing the address from the web]]
RSpec.describe "Changing an address from the web Profile page", type: :system, js: true do
  let!(:sway_locale) { create(:sway_locale, city: "Baltimore", state: "MD", country: "US") }
  let!(:old_district) { create(:district, sway_locale: sway_locale, name: "MD1") }
  let!(:old_legislator) { create(:legislator, district: old_district, sway_locale: sway_locale) }
  let!(:new_district) { create(:district, sway_locale: sway_locale, name: "MD2") }
  let!(:new_legislator) { create(:legislator, district: new_district, sway_locale: sway_locale) }
  let!(:user) { complete_registration_with_active_link(create(:user), legislator: old_legislator) }
  let!(:old_address) do
    create(:address, street: "100 N Holliday St", city: "Baltimore", region_code: "MD", postal_code: "21202",
      country: "US", latitude: 39.29105, longitude: -76.61069)
  end

  def nominatim_place(place_id:, number:, road:, lat:, lon:)
    {
      "place_id" => place_id,
      "lat" => lat,
      "lon" => lon,
      "display_name" => "#{number} #{road}, Baltimore, MD 21202, USA",
      "address" => {
        "house_number" => number, "road" => road, "city" => "Baltimore", "state" => "Maryland",
        "postcode" => "21202", "country" => "United States", "country_code" => "us", "ISO3166-2-lvl4" => "US-MD"
      }
    }
  end

  around do |example|
    with_env("GOOGLE_MAPS_API_KEY" => nil) { example.run }
  end

  before do
    create(:legislator_term, legislator: old_legislator, district: old_district)
    create(:legislator_term, legislator: new_legislator, district: new_district)
    create(:user_district, user: user, district: old_district, active: true)
    UserAddress.create!(user: user, address: old_address)

    allow(SwayLocale).to receive(:find_or_create_by_normalized!).and_return(sway_locale)
    allow_any_instance_of(SwayRegistrationService).to receive(:district_legislators).and_return([new_legislator]) # rubocop:disable RSpec/AnyInstance
    stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
      .with(query: hash_including("q" => /Light/))
      .to_return(status: 200, headers: {"Content-Type" => "application/json"},
        body: [nominatim_place(place_id: 1, number: "100", road: "Light St", lat: "39.2851", lon: "-76.6141")].to_json)
    stub_request(:get, %r{nominatim\.openstreetmap\.org/search})
      .with(query: hash_including("q" => /Pratt/))
      .to_return(status: 200, headers: {"Content-Type" => "application/json"},
        body: [nominatim_place(place_id: 2, number: "1", road: "E Pratt St", lat: "39.2867", lon: "-76.6122")].to_json)
  end

  def open_address_from_profile
    visit "/profile"
    wait_until_loaded
    find("[data-testid='profile-account-links']", wait: 10).click_link("Address")
    expect(page).to have_css("h1", text: "Address", wait: 10)
  end

  def switch_to(search_text, suggestion_text)
    fill_in "Address", with: search_text
    find("[role='option']", text: suggestion_text, wait: 10).click
    find("[data-testid='btn-submit-registration']:not([disabled])").click
    within("[data-testid='confirm-address-switch-dialog']", wait: 10) do
      expect(page).to have_text("Switching your address will deactivate your current representative links")
      find("[data-testid='btn-confirm-address-switch']").click
    end
  end

  it "switches the address after a confirmation, then shows the cooldown on a second switch" do
    sign_in_as(user)
    open_address_from_profile
    expect(page).to have_css("[data-testid='current-address']", text: "100 N Holliday St")

    switch_to("100 Light", "100 Light St")

    expect(page).to have_current_path("/feed", ignore_query: true, wait: 20)
    expect(UserAddressChange.where(user: user).count).to eq(1)
    expect(user.reload.address.street).to eq("100 Light St")
    expect(user.user_legislators.find_by(legislator: old_legislator).active).to be(false)
    expect(user.user_legislators.find_by(legislator: new_legislator).active).to be(true)
    expect(user.user_districts.find_by(district: new_district).active).to be(true)

    open_address_from_profile
    switch_to("1 E Pratt", "1 E Pratt St")

    expect(page).to have_text(SwayRegistrationController::REGISTRATION_ADDRESS_SWITCH_COOLDOWN_MESSAGE, wait: 20)
    expect(page).to have_current_path("/users/address/edit", ignore_query: true)
    expect(UserAddressChange.where(user: user).count).to eq(1)
    expect(user.reload.address.street).to eq("100 Light St")
  end
end
