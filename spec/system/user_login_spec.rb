# frozen_string_literal: true

require "rails_helper"

RSpec.describe "User Login", type: :system, js: true do
  include_context "TwilioDouble"

  let(:phone) do
    "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"
  end

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
    # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
    create(:sway_locale, :baltimore)

    visit root_path
    @active_authenticators = [enable_virtual_authenticator]
  end

  after do
    Array(@active_authenticators).reverse_each do |id|
      disable_virtual_authenticator(id)
    end
  end

  it "logs in an existing registered user and redirects to legislators" do
    user = register_passkey_user(phone: phone)
    complete_registration_with_active_link(user)

    start_session =
      browser_json_request(
        "POST",
        users_webauthn_sessions_path,
        {phone: phone}
      )
    expect(start_session.fetch("status")).to eq(200)
    # The server wraps the challenge in a {flow: "passkey", options:} envelope.
    expect(start_session.dig("body", "flow")).to eq("passkey")

    assertion = browser_get_credential(start_session.dig("body", "options"))
    expect(assertion.fetch("id")).to be_present

    complete_auth =
      browser_json_request(
        "POST",
        callback_users_webauthn_sessions_path,
        {publicKeyCredential: assertion}
      )
    # On success the callback redirects to feed_path, which is how
    # Inertia expects a successful post to end.
    expect(complete_auth.fetch("status")).to eq(303)

    # The session exists, so visiting the feed page is not bounced.
    visit feed_path
    expect(page).to have_current_path(
      feed_path,
      ignore_query: true,
      wait: CapybaraHelpers::SECONDS_TO_WAIT
    )
    # @lat: [[identity-and-access#The sign-in challenge says which ceremony to run]]
  end

  # @lat: [[identity-and-access#The sign-in challenge says which ceremony to run]]
  it "logs in through the real passkey UI and renders the feed page" do
    user = register_passkey_user(phone: phone)
    complete_registration_with_active_link(user)

    # register_passkey_user leaves the user signed in, so clear the cookies to
    # get the logged-out login form on the home page. The fake authenticator is
    # a separate thing, so the passkey stored on it survives.
    page.driver.browser.manage.delete_all_cookies

    visit root_path
    fill_in "Phone number", with: phone
    click_button "Continue with Phone"

    # The chain: the page starts authentication, the browser asks the fake
    # authenticator for a signature, the result is posted back for checking, and
    # the server signs the user in and redirects to the feed page.
    expect(page).to have_current_path(
      feed_path,
      ignore_query: true,
      wait: CapybaraHelpers::SECONDS_TO_WAIT
    )
    expect(page).to have_text("Feed")
  end

  it "rejects login when passkey challenge is tampered" do
    user = register_passkey_user(phone: phone)
    complete_registration_with_active_link(user)

    start_session =
      browser_json_request(
        "POST",
        users_webauthn_sessions_path,
        {phone: phone}
      )
    expect(start_session.fetch("status")).to eq(200)

    assertion =
      browser_get_credential(
        start_session.dig("body", "options"),
        challenge_override: random_base64url
      )

    # @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Discoverable callback resolves the credential owner]]
    passkey = user.passkeys.last
    sign_count_before = passkey.sign_count
    last_used_before = passkey.last_used_at

    callback =
      browser_json_request(
        "POST",
        callback_users_webauthn_sessions_path,
        {publicKeyCredential: assertion}
      )
    # A WebAuthn::Error redirects to the home page with an alert in the flash.
    expect(callback.fetch("status")).to eq(303)

    # @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Discoverable callback resolves the credential owner]]
    passkey.reload
    expect(passkey.sign_count).to eq(sign_count_before)
    expect(passkey.last_used_at).to eq(last_used_before)
  end
end
