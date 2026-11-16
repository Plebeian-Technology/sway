# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Signup passkey failure handling", type: :system, js: true do
  include_context "TwilioDouble"

  around do |example|
    with_env(
      "TWILIO_ACCOUNT_SID" => "test-sid",
      "TWILIO_AUTH_TOKEN" => "test-token",
      "OPEN_STATES_API_KEY" => "test-open-states-key",
      "GOOGLE_MAPS_API_KEY" => nil
    ) do
      with_app_config(:dev_login, skip_phone_verification: false) { example.run }
    end
  end

  before do
    ActiveJob::Base.queue_adapter = :test
  end

  after do
    disable_virtual_authenticator(@authenticator_id) if @authenticator_id
  end

  describe "cancelled passkey prompt retry" do
    # @lat: [[lat.md/explanation/signup-passkey-failure-browser-tests#Signup passkey failure browser tests#Cancelled passkey prompt retry]]
    it "allows retrying passkey creation after browser prompt cancellation through to a finished account" do
      baltimore_locale = create(:sway_locale, :baltimore)
      congress_locale = create(:sway_locale, :congress)
      setup_baltimore_and_congress_districts(baltimore_locale, congress_locale)
      stub_baltimore_address_lookups

      not_found_error = Twilio::REST::RestError.allocate
      allow(not_found_error).to receive_messages(
        code: 20_404,
        status_code: 404,
        message: "VerificationCheck was not found",
        full_message: "VerificationCheck was not found"
      )

      check_calls = 0
      allow(twilio_verification_checks_double).to receive(:create) do
        check_calls += 1
        raise not_found_error if check_calls > 1

        twilio_verification_result
      end

      registration_create_calls = 0
      subscriber =
        ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*, payload|
          if payload[:controller] == "Users::Webauthn::RegistrationController" && payload[:action] == "create"
            registration_create_calls += 1
          end
        end

      phone = generate_phone_number

      begin
        boot_home_with_virtual_authenticator

        with_phone_verify_rate_limit_for_browser do
          fill_in "Phone number", with: phone
          click_button "Continue with Phone"

          expect(page).to have_field("v2-code", wait: 10)
          fill_in "v2-code", with: "123456"
          reject_next_passkey_creation
          click_button "Confirm code"

          expect(page).to have_text(
            "Passkey setup did not finish. Press Confirm code to try again, or use another browser or device if it keeps failing.",
            wait: 10
          )
          expect(page).to have_no_text("Error in Sway")
          expect(page).to have_no_text("Code not found.")
          expect(page).to have_field("v2-code")
          expect(page).to have_button("Confirm code", disabled: false)

          click_button "Confirm code"

          expect(page).to have_current_path(sway_registration_index_path, wait: 15)
          expect(page).to have_css("h1", text: "Complete your registration")
        end

        fill_in "Address", with: "100 N Holliday"
        find("[role='option']", text: "100 N Holliday St", wait: 10).click
        find("[data-testid='btn-submit-registration']").click

        expect(page).to have_current_path(feed_path, ignore_query: true, wait: 15)

        user = User.find_by!(phone: phone)
        expect(user.passkeys.count).to eq(1)
        expect(user.is_registration_complete).to be(true)
        expect(user.registration_status).to eq("completed")
        expect(twilio_verification_checks_double).to have_received(:create).once
        expect(twilio_verifications_double).to have_received(:create).once
        expect(registration_create_calls).to be_between(1, 5)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end
  end

  describe "passkey enrollment callback failures" do
    # @lat: [[lat.md/explanation/signup-passkey-failure-browser-tests#Signup passkey failure browser tests#Expired registration session callback toast]]
    it "shows the expired-session toast on the Home page when registration options are missing" do
      phone = generate_phone_number
      boot_home_with_virtual_authenticator

      start_sms_session_and_verify_phone(phone)
      credential = browser_create_credential(synthetic_registration_options(phone))
      callback =
        browser_json_request(
          "POST",
          callback_users_webauthn_registration_index_path,
          credential.merge("passkey_label" => "Sway")
        )
      expect(callback.fetch("status")).to eq(303)

      visit root_path
      expect(page).to have_text("Registration session expired. Please try again.", wait: 10)
      expect(page).to have_button("Continue with Phone", disabled: false)
    end

    # @lat: [[lat.md/explanation/signup-passkey-failure-browser-tests#Signup passkey failure browser tests#Stale challenge verification failure toast]]
    it "shows the verification-failed toast on the Home page when the credential challenge is stale" do
      phone = generate_phone_number
      boot_home_with_virtual_authenticator

      start_sms_session_and_verify_phone(phone)
      first_options = request_registration_options
      credential = browser_create_credential(first_options)
      request_registration_options

      callback =
        browser_json_request(
          "POST",
          callback_users_webauthn_registration_index_path,
          credential.merge("passkey_label" => "Sway")
        )
      expect(callback.fetch("status")).to eq(303)

      visit root_path
      expect(page).to have_text(Users::Webauthn::RegistrationController::VERIFICATION_FAILED_MESSAGE, wait: 10)
      expect(page).to have_button("Continue with Phone", disabled: false)
    end

    # @lat: [[lat.md/explanation/signup-passkey-failure-browser-tests#Signup passkey failure browser tests#Already registered phone callback toast]]
    it "shows the already-registered toast on the Home page when the phone gains a passkey mid-flow" do
      phone = generate_phone_number
      boot_home_with_virtual_authenticator

      start_sms_session_and_verify_phone(phone)
      options = request_registration_options
      credential = browser_create_credential(options)

      existing_user = create(:user, phone: phone, is_phone_verified: true)
      create(:passkey, user: existing_user)

      callback =
        browser_json_request(
          "POST",
          callback_users_webauthn_registration_index_path,
          credential.merge("passkey_label" => "Sway")
        )
      expect(callback.fetch("status")).to eq(303)

      visit root_path
      expect(page).to have_text(Users::Webauthn::RegistrationController::ALREADY_REGISTERED_MESSAGE, wait: 10)
      expect(page).to have_button("Continue with Phone", disabled: false)
    end

    # @lat: [[lat.md/explanation/signup-passkey-failure-browser-tests#Signup passkey failure browser tests#Resume enrollment after expired session toast]]
    it "resumes enrollment without sending a second SMS after an expired-session redirect" do
      phone = generate_phone_number
      boot_home_with_virtual_authenticator

      start_sms_session_and_verify_phone(phone)
      credential = browser_create_credential(synthetic_registration_options(phone))
      callback =
        browser_json_request(
          "POST",
          callback_users_webauthn_registration_index_path,
          credential.merge("passkey_label" => "Sway")
        )
      expect(callback.fetch("status")).to eq(303)

      visit root_path
      expect(page).to have_text("Registration session expired. Please try again.", wait: 10)
      expect(page).to have_button("Continue with Phone", disabled: false)
      expect(page).to have_no_css("#application-loading")

      with_phone_verify_rate_limit_for_browser do
        fill_in "Phone number", with: phone
        click_button "Continue with Phone"

        expect(page).to have_current_path(sway_registration_index_path, wait: 15)
        expect(page).to have_css("h1", text: "Complete your registration")
      end

      expect(twilio_verifications_double).to have_received(:create).once
      expect(User.find_by!(phone: phone).passkeys.count).to eq(1)
    end

    # @lat: [[lat.md/explanation/signup-passkey-failure-browser-tests#Signup passkey failure browser tests#Resume enrollment after verification failed toast]]
    it "resumes enrollment without sending a second SMS after a verification-failed redirect" do
      phone = generate_phone_number
      boot_home_with_virtual_authenticator

      start_sms_session_and_verify_phone(phone)
      first_options = request_registration_options
      credential = browser_create_credential(first_options)
      request_registration_options

      callback =
        browser_json_request(
          "POST",
          callback_users_webauthn_registration_index_path,
          credential.merge("passkey_label" => "Sway")
        )
      expect(callback.fetch("status")).to eq(303)

      visit root_path
      expect(page).to have_text(Users::Webauthn::RegistrationController::VERIFICATION_FAILED_MESSAGE, wait: 10)
      expect(page).to have_button("Continue with Phone", disabled: false)
      expect(page).to have_no_css("#application-loading")

      with_phone_verify_rate_limit_for_browser do
        fill_in "Phone number", with: phone
        click_button "Continue with Phone"

        expect(page).to have_current_path(sway_registration_index_path, wait: 15)
        expect(page).to have_css("h1", text: "Complete your registration")
      end

      expect(twilio_verifications_double).to have_received(:create).once
      expect(User.find_by!(phone: phone).passkeys.count).to eq(1)
    end
  end

  describe "unfinished account sign-in routing" do
    # @lat: [[lat.md/explanation/signup-passkey-failure-browser-tests#Signup passkey failure browser tests#Unfinished account discoverable sign-in routing]]
    it "routes an unfinished passkey holder to the address form on discoverable sign-in" do
      phone = generate_phone_number
      boot_home_with_virtual_authenticator

      user = register_passkey_user(phone: phone)
      expect(user.is_registration_complete).to be(false)
      expect(user.user_address).to be_nil

      page.driver.browser.manage.delete_all_cookies
      visit root_path
      expect(page).to have_button("Continue with Phone", disabled: false, wait: 10)
      expect(page).to have_no_css("#application-loading")

      click_button "Sign in with a passkey"

      expect(page).to have_current_path(sway_registration_index_path, wait: 15)
      expect(page).to have_css("h1", text: "Complete your registration")
      expect(find_field("Address", visible: :visible)).to be_visible
    end

    # @lat: [[lat.md/explanation/signup-passkey-failure-browser-tests#Signup passkey failure browser tests#Unfinished account phone-first sign-in routing]]
    it "routes an unfinished passkey holder to the address form on phone-first passkey sign-in" do
      phone = generate_phone_number
      boot_home_with_virtual_authenticator

      user = register_passkey_user(phone: phone)
      expect(user.is_registration_complete).to be(false)
      expect(user.user_address).to be_nil

      page.driver.browser.manage.delete_all_cookies
      visit root_path
      expect(page).to have_button("Continue with Phone", disabled: false, wait: 10)
      expect(page).to have_no_css("#application-loading")

      fill_in "Phone number", with: phone
      click_button "Continue with Phone"

      expect(page).to have_current_path(sway_registration_index_path, wait: 15)
      expect(page).to have_css("h1", text: "Complete your registration")
      expect(find_field("Address", visible: :visible)).to be_visible
    end
  end

  def generate_phone_number
    "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"
  end

  def boot_home_with_virtual_authenticator
    visit root_path
    expect(page).to have_button("Continue with Phone", disabled: false, wait: 10)
    expect(page).to have_no_css("#application-loading")
    wait_until do
      page.evaluate_script(
        "performance.getEntriesByType('resource').some((entry) => entry.name.endsWith('/api/v1/funnel_events'))"
      )
    end
    @authenticator_id = enable_virtual_authenticator
  end

  def with_phone_verify_rate_limit_for_browser
    current_origin = page.evaluate_script("window.location.origin").to_s
    current_host = URI.parse(current_origin).host
    with_app_config(:webauthn, rp_id: current_host, allowed_origins: [current_origin]) do
      with_rate_limit_enabled(:phone_verify) { yield }
    end
  end

  def start_sms_session_and_verify_phone(phone)
    start_session = browser_json_request("POST", users_webauthn_sessions_path, {phone: phone})
    expect(start_session.fetch("status")).to eq(200)
    expect(start_session.dig("body", "flow")).to eq("sms")
    expect(start_session.dig("body", "success")).to eq(true)

    verify_phone =
      browser_json_request(
        "PATCH",
        phone_verification_path(1),
        {phone: phone, code: "123456"}
      )
    expect(verify_phone.fetch("status")).to eq(200)
    expect(verify_phone.dig("body", "success")).to eq(true)
  end

  def request_registration_options
    response =
      browser_json_request(
        "POST",
        users_webauthn_registration_index_path,
        {phone: "", passkey_label: "Sway"}
      )
    expect(response.fetch("status")).to eq(200)
    response.fetch("body")
  end

  def synthetic_registration_options(phone)
    current_host = URI.parse(page.evaluate_script("window.location.origin").to_s).host
    {
      "challenge" => random_base64url,
      "rp" => {"name" => "Sway", "id" => current_host},
      "user" => {"id" => random_base64url, "name" => phone, "displayName" => phone},
      "pubKeyCredParams" => [{"type" => "public-key", "alg" => -7}],
      "authenticatorSelection" => {"residentKey" => "preferred", "userVerification" => "required"}
    }
  end

  def setup_baltimore_and_congress_districts(baltimore_locale, congress_locale)
    baltimore_address = Address.new(latitude: 39.29105, longitude: -76.61069)
    district_number = SwayGeocode::Local.new(baltimore_locale, baltimore_address).districts.last
    baltimore_district = create(:district, name: "MD#{district_number}", sway_locale: baltimore_locale)
    baltimore_rep = create(:legislator, district: baltimore_district, sway_locale: baltimore_locale, active: true)
    baltimore_seat =
      Seat.find_or_create_by_identity!(
        district: baltimore_district,
        office_identity: "baltimore-district-#{district_number}",
        title: "Test representative",
        chamber: "House"
      )
    create(:legislator_term, legislator: baltimore_rep, district: baltimore_district, seat: baltimore_seat)

    congress_district = create(:district, name: "MD7", sway_locale: congress_locale)
    congress_rep = create(:legislator, district: congress_district, sway_locale: congress_locale, active: true)
    congress_seat =
      Seat.find_or_create_by_identity!(
        district: congress_district,
        office_identity: "congress-district-md7",
        title: "Rep.",
        chamber: "House of Representatives"
      )
    create(:legislator_term, legislator: congress_rep, district: congress_district, seat: congress_seat, title: "Rep.")
  end

  def stub_baltimore_address_lookups
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
  end
end
