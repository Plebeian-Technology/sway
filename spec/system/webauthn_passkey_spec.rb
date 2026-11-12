# frozen_string_literal: true

require "rails_helper"

RSpec.describe "WebAuthn Passkey", type: :system, js: true, phase16: true do
  let(:phone) do
    "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"
  end
  let(:default_env) do
    {
      "TWILIO_ACCOUNT_SID" => "test-sid",
      "TWILIO_AUTH_TOKEN" => "test-token"
    }
  end

  around do |example|
    initial_values = {} #: Hash[String, String?]
    previous_values =
      default_env.each_with_object(initial_values) do |(key, _value), memo|
        memo[key] = ENV.fetch(key, nil)
      end

    begin
      default_env.each { |key, value| ENV[key] = value }

      # The stand-in account and the skip switch both moved to
      # Sway::Settings.dev_login. The server runs in a thread of
      # this same process, so the swapped instance is visible to it.
      with_app_config(
        :dev_login,
        skip_phone_verification: true,
        dev_account_full_name: "Passkey+User",
        dev_account_sway_locale: "baltimore-maryland-united_states"
      ) { example.run }
    ensure
      previous_values.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end
  end

  before do
    # The stand-in account's address comes from this locale's sample address.
    create(:sway_locale, :baltimore)
    visit root_path
    @active_authenticators = [enable_virtual_authenticator]
  end

  after do
    Array(@active_authenticators).reverse_each do |id|
      disable_virtual_authenticator(id)
    end
  end

  it "registers a new passkey user through the full browser flow" do
    start_session =
      browser_json_request("POST", users_webauthn_sessions_path, {phone:})
    # Every start answers 200 with a {flow:} envelope, and a phone the app has
    # never seen gets the sms flow.
    expect(start_session.fetch("status")).to eq(200)
    expect(start_session.dig("body", "flow")).to eq("sms")
    expect(start_session.dig("body", "success")).to eq(true)

    verify_phone =
      browser_json_request(
        "PATCH",
        phone_verification_path(1),
        {phone:, code: "123456"}
      )
    expect(verify_phone.fetch("status")).to eq(200)
    expect(verify_phone.dig("body", "success")).to eq(true)

    registration_options =
      browser_json_request(
        "POST",
        users_webauthn_registration_index_path,
        {full_name: "Passkey User"}
      )
    expect(registration_options.fetch("status")).to eq(200)

    credential = browser_create_credential(registration_options.fetch("body"))
    expect(credential.fetch("id")).to be_present

    complete_registration =
      browser_json_request(
        "POST",
        callback_users_webauthn_registration_index_path,
        credential.merge("passkey_label" => "System Test Passkey")
      )
    # The registration callback answers with a redirect to
    # sway_registration_index_path.
    expect(complete_registration.fetch("status")).to eq(303)

    visit sway_registration_index_path
    expect(page).to have_current_path(
      /(sway_registration|legislators)/,
      ignore_query: true,
      wait: 10
    )

    user = User.find_by!(phone:)
    expect(user).to be_present
    expect(user.passkeys.count).to eq(1)
  end

  it "authenticates an existing passkey user and routes to legislators" do
    user = register_passkey_user(phone:)
    complete_registration_with_active_link(user)

    start_session =
      browser_json_request("POST", users_webauthn_sessions_path, {phone:})
    expect(start_session.fetch("status")).to eq(200)
    # The server wraps the challenge in a {flow: "passkey", options:} envelope.
    expect(start_session.dig("body", "flow")).to eq("passkey")

    assertion = browser_get_credential(start_session.dig("body", "options"))
    expect(assertion.fetch("id")).to be_present

    complete_authentication =
      browser_json_request(
        "POST",
        callback_users_webauthn_sessions_path,
        {publicKeyCredential: assertion}
      )
    # The sign-in callback answers with a redirect to feed_path.
    expect(complete_authentication.fetch("status")).to eq(303)

    visit feed_path
    expect(page).to have_current_path(
      feed_path,
      ignore_query: true,
      wait: 10
    )
  end

  it "handles canceled browser prompt without posting callback" do
    user = register_passkey_user(phone:)
    complete_registration_with_active_link(user)

    start_session =
      browser_json_request("POST", users_webauthn_sessions_path, {phone:})
    expect(start_session.fetch("status")).to eq(200)

    canceled = browser_cancel_get_credential(start_session.dig("body", "options"))
    expect(canceled.fetch("ok")).to eq(false)
    expect(canceled.fetch("name")).to eq("AbortError")

    # Record what the server has stored for this passkey before the callback,
    # which is sent with an empty body. On success the server bumps sign_count
    # and last_used_at and signs the user in; a canceled prompt must touch
    # neither. A 303 on its own looks exactly like the success redirect.
    passkey = user.passkeys.last
    sign_count_before = passkey.sign_count
    last_used_before = passkey.last_used_at

    callback =
      browser_json_request("POST", callback_users_webauthn_sessions_path, {})
    # The error path redirects to the home page with an alert in the flash.
    expect(callback.fetch("status")).to eq(303)

    # The stored passkey is untouched. That is what tells a real sign-in from a
    # refused one here; user_login_spec's tampering example spells out why. A
    # canceled prompt with an empty callback must never reach
    # stored_passkey.update!.
    passkey.reload
    expect(passkey.sign_count).to eq(sign_count_before)
    expect(passkey.last_used_at).to eq(last_used_before)
  end

  it "rejects authentication when challenge is tampered" do
    user = register_passkey_user(phone:)
    complete_registration_with_active_link(user)

    start_session =
      browser_json_request("POST", users_webauthn_sessions_path, {phone:})
    expect(start_session.fetch("status")).to eq(200)

    assertion =
      browser_get_credential(
        start_session.dig("body", "options"),
        challenge_override: random_base64url
      )

    # Record what the server has stored for this passkey before the callback. On
    # success the server bumps sign_count and last_used_at and signs the user
    # in; a tampered challenge must touch neither. A 303 on its own is identical
    # to the success redirect.
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

    # The stored passkey is untouched. That is what tells a real sign-in from a
    # refused one here; user_login_spec's tampering example spells out why. A
    # tampered challenge must never reach stored_passkey.update!.
    passkey.reload
    expect(passkey.sign_count).to eq(sign_count_before)
    expect(passkey.last_used_at).to eq(last_used_before)
  end

  it "rejects unknown credential during browser authentication" do
    known_phone =
      "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"
    unknown_phone =
      "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"

    user = register_passkey_user(phone: known_phone)
    complete_registration_with_active_link(user)

    disable_virtual_authenticator(@active_authenticators.pop)
    second_authenticator = enable_virtual_authenticator
    @active_authenticators << second_authenticator

    register_passkey_user(phone: unknown_phone)

    start_session =
      browser_json_request(
        "POST",
        users_webauthn_sessions_path,
        {phone: known_phone}
      )
    expect(start_session.fetch("status")).to eq(200)

    random_unknown_id =
      Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false)

    expect do
      browser_get_credential(
        start_session.dig("body", "options"),
        allow_credentials_override: [
          {"id" => random_unknown_id, "type" => "public-key"}
        ]
      )
    end.to raise_error(RuntimeError, /NotAllowedError/)
  end
end
