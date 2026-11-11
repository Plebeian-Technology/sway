# frozen_string_literal: true

require "rails_helper"

# @lat: [[influence-page-browser-coverage#The system examples cover the signed-in page outcomes]]
RSpec.describe "Influence Page", type: :system, js: true do
  include_context "TwilioDouble"

  let(:sway_locale) do
    SwayLocale.find_by(city: "baltimore", state: "MD", country: "United States") ||
      create(:sway_locale, city: "baltimore", state: "MD", country: "United States")
  end
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }

  around do |example|
    initial_values = {} #: Hash[String, String?]
    env_overrides = {
      "TWILIO_ACCOUNT_SID" => "test-sid",
      "TWILIO_AUTH_TOKEN" => "test-token"
    }
    previous_values =
      env_overrides.each_with_object(initial_values) do |(key, _value), memo|
        memo[key] = ENV.fetch(key, nil)
      end

    begin
      env_overrides.each { |key, value| ENV[key] = value }

      example.run
    ensure
      previous_values.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end
  end

  before do
    sway_locale

    visit root_path
    @active_authenticators = [enable_virtual_authenticator]

    phone = "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"
    @signed_in_user = register_passkey_user(phone: phone)
    create(
      :address,
      city: "baltimore",
      region_code: "MD",
      country: "United States"
    ).tap { |address| set_user_address(@signed_in_user, address) }
    create(:user_legislator, user: @signed_in_user, legislator: legislator, active: true)
    @signed_in_user.complete!
  end

  after do
    Array(@active_authenticators).reverse_each do |id|
      disable_virtual_authenticator(id)
    end
  end

  it "renders the influence panel for a registration-complete user" do
    visit influence_index_path

    expect(page).to have_text("Your influence in", wait: 10)
  end

  # @lat: [[influence-page-browser-coverage#Redirect cases belong to request coverage]]
end
