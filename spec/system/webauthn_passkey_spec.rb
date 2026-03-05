# frozen_string_literal: true

require "rails_helper"

RSpec.describe "WebAuthn Passkey", type: :system, js: true do
  let(:phone) do
    "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"
  end
  let(:default_env) do
    {
      "SKIP_PHONE_VERIFICATION" => "1",
      "DEFAULT_USER_FULL_NAME" => "Passkey+User",
      "DEFAULT_CITY" => "Baltimore",
      "DEFAULT_REGION_CODE" => "MD",
      "DEFAULT_POSTAL_CODE" => "21224",
      "DEFAULT_STREET" => "123+Main+St",
      "DEFAULT_LATITUDE" => "39.2904",
      "DEFAULT_LONGITUDE" => "-76.6122",
      "TWILIO_ACCOUNT_SID" => "test-sid",
      "TWILIO_AUTH_TOKEN" => "test-token",
    }
  end

  around do |example|
    previous_server_host = Capybara.server_host
    previous_app_host = Capybara.app_host
    previous_always_include_port = Capybara.always_include_port

    Capybara.server_host = "localhost"
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true

    initial_values = Hash.new #: Hash[String, String?]
    previous_values =
      default_env.each_with_object(initial_values) do |(key, _value), memo|
        memo[key] = ENV.fetch(key, nil)
      end
    default_env.each { |key, value| ENV[key] = value }

    example.run
  ensure
    Capybara.server_host = previous_server_host
    Capybara.app_host = previous_app_host
    Capybara.always_include_port = previous_always_include_port

    previous_values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  before do
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
      browser_json_request("POST", users_webauthn_sessions_path, { phone: })
    expect(start_session.fetch("status")).to eq(202)
    expect(start_session.dig("body", "success")).to eq(true)

    verify_phone =
      browser_json_request(
        "PATCH",
        phone_verification_path(1),
        { phone:, code: "123456" },
      )
    expect(verify_phone.fetch("status")).to eq(200)
    expect(verify_phone.dig("body", "success")).to eq(true)

    registration_options =
      browser_json_request(
        "POST",
        users_webauthn_registration_index_path,
        { full_name: "Passkey User" },
      )
    expect(registration_options.fetch("status")).to eq(200)

    credential = browser_create_credential(registration_options.fetch("body"))
    expect(credential.fetch("id")).to be_present

    complete_registration =
      browser_json_request(
        "POST",
        callback_users_webauthn_registration_index_path,
        credential.merge("passkey_label" => "System Test Passkey"),
      )
    expect(complete_registration.fetch("status")).to eq(200)
    expect(complete_registration.dig("body", "route")).to eq(
      SwayRoutes::REGISTRATION,
    )

    visit complete_registration.dig("body", "route")
    expect(page).to have_current_path(
      /(sway_registration|legislators)/,
      ignore_query: true,
      wait: 10,
    )

    user = User.find_by!(phone:)
    expect(user).to be_present
    expect(user.passkeys.count).to eq(1)
  end

  it "authenticates an existing passkey user and routes to legislators" do
    user = register_passkey_user(phone:)
    user.update!(
      is_registration_complete: true,
      registration_status: "completed",
    )

    start_session =
      browser_json_request("POST", users_webauthn_sessions_path, { phone: })
    expect(start_session.fetch("status")).to eq(200)

    assertion = browser_get_credential(start_session.fetch("body"))
    expect(assertion.fetch("id")).to be_present

    complete_authentication =
      browser_json_request(
        "POST",
        callback_users_webauthn_sessions_path,
        { publicKeyCredential: assertion },
      )
    expect(complete_authentication.fetch("status")).to eq(200)
    expect(complete_authentication.dig("body", "route")).to eq(legislators_path)

    visit complete_authentication.dig("body", "route")
    expect(page).to have_current_path(
      legislators_path,
      ignore_query: true,
      wait: 10,
    )
  end

  it "handles canceled browser prompt without posting callback" do
    user = register_passkey_user(phone:)
    user.update!(
      is_registration_complete: true,
      registration_status: "completed",
    )

    start_session =
      browser_json_request("POST", users_webauthn_sessions_path, { phone: })
    expect(start_session.fetch("status")).to eq(200)

    canceled = browser_cancel_get_credential(start_session.fetch("body"))
    expect(canceled.fetch("ok")).to eq(false)
    expect(canceled.fetch("name")).to eq("AbortError")

    callback =
      browser_json_request("POST", callback_users_webauthn_sessions_path, {})
    expect(callback.fetch("status")).to eq(422)
    expect(callback.dig("body", "message")).to include(
      "missing publicKeyCredential",
    )
  end

  it "rejects authentication when challenge is tampered" do
    user = register_passkey_user(phone:)
    user.update!(
      is_registration_complete: true,
      registration_status: "completed",
    )

    start_session =
      browser_json_request("POST", users_webauthn_sessions_path, { phone: })
    expect(start_session.fetch("status")).to eq(200)

    assertion =
      browser_get_credential(
        start_session.fetch("body"),
        challenge_override: random_base64url,
      )

    callback =
      browser_json_request(
        "POST",
        callback_users_webauthn_sessions_path,
        { publicKeyCredential: assertion },
      )
    expect(callback.fetch("status")).to eq(422)
    expect(callback.dig("body", "message")).to include("Verification failed")
  end

  it "rejects unknown credential during browser authentication" do
    known_phone =
      "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"
    unknown_phone =
      "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"

    user = register_passkey_user(phone: known_phone)
    user.update!(
      is_registration_complete: true,
      registration_status: "completed",
    )

    disable_virtual_authenticator(@active_authenticators.pop)
    second_authenticator = enable_virtual_authenticator
    @active_authenticators << second_authenticator

    register_passkey_user(phone: unknown_phone)

    start_session =
      browser_json_request(
        "POST",
        users_webauthn_sessions_path,
        { phone: known_phone },
      )
    expect(start_session.fetch("status")).to eq(200)

    random_unknown_id =
      Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false)

    expect do
      browser_get_credential(
        start_session.fetch("body"),
        allow_credentials_override: [
          { "id" => random_unknown_id, "type" => "public-key" },
        ],
      )
    end.to raise_error(RuntimeError, /NotAllowedError/)
  end

  def register_passkey_user(phone:)
    start_session =
      browser_json_request("POST", users_webauthn_sessions_path, { phone: })
    expect(start_session.fetch("status")).to eq(202)
    expect(start_session.dig("body", "success")).to eq(true)

    verify_phone =
      browser_json_request(
        "PATCH",
        phone_verification_path(1),
        { phone:, code: "123456" },
      )
    expect(verify_phone.fetch("status")).to eq(200)
    expect(verify_phone.dig("body", "success")).to eq(true)

    registration_options =
      browser_json_request(
        "POST",
        users_webauthn_registration_index_path,
        { full_name: "Passkey User" },
      )
    expect(registration_options.fetch("status")).to eq(200)

    credential = browser_create_credential(registration_options.fetch("body"))
    callback =
      browser_json_request(
        "POST",
        callback_users_webauthn_registration_index_path,
        credential.merge("passkey_label" => "System Test Passkey"),
      )
    expect(callback.fetch("status")).to eq(200)

    User.find_by!(phone:)
  end

  def random_base64url
    Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false)
  end

  def browser_create_credential(public_key_options)
    browser_webauthn_credential("create", public_key_options)
  end

  def browser_get_credential(
    public_key_options,
    challenge_override: nil,
    allow_credentials_override: nil
  )
    browser_webauthn_credential(
      "get",
      public_key_options,
      challengeOverride: challenge_override,
      allowCredentialsOverride: allow_credentials_override,
    )
  end

  def browser_cancel_get_credential(public_key_options)
    script = <<~JS
      const options = arguments[0];
      const done = arguments[arguments.length - 1];

      const b64urlToArrayBuffer = (value) => {
        const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
        const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
        const binary = atob(padded);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
        return bytes.buffer;
      };

      const parseOptions = (opts) => {
        if (typeof PublicKeyCredential.parseRequestOptionsFromJSON === "function") {
          return PublicKeyCredential.parseRequestOptionsFromJSON(opts);
        }

        const parsed = { ...opts, challenge: b64urlToArrayBuffer(opts.challenge) };
        if (Array.isArray(opts.allowCredentials)) {
          parsed.allowCredentials = opts.allowCredentials.map((credential) => ({
            ...credential,
            id: b64urlToArrayBuffer(credential.id),
          }));
        }
        return parsed;
      };

      const controller = new AbortController();
      controller.abort();

      navigator.credentials
        .get({ publicKey: parseOptions(options), signal: controller.signal })
        .then(() => done({ ok: true }))
        .catch((error) => done({ ok: false, name: error.name, message: error.message }));
    JS

    page.driver.browser.execute_async_script(script, public_key_options)
  end

  def browser_webauthn_credential(method, public_key_options, overrides = {})
    script = <<~JS
      const method = arguments[0];
      const options = arguments[1];
      const overrides = arguments[2] || {};
      const done = arguments[arguments.length - 1];

      const b64urlToArrayBuffer = (value) => {
        const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
        const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
        const binary = atob(padded);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
        return bytes.buffer;
      };

      const arrayBufferToB64url = (buffer) => {
        const bytes = new Uint8Array(buffer);
        let binary = "";
        for (let i = 0; i < bytes.length; i += 1) binary += String.fromCharCode(bytes[i]);
        return btoa(binary).replace(/\\+/g, "-").replace(/\\//g, "_").replace(/=+$/, "");
      };

      const parseCreateOptions = (opts) => {
        if (typeof PublicKeyCredential.parseCreationOptionsFromJSON === "function") {
          return PublicKeyCredential.parseCreationOptionsFromJSON(opts);
        }

        const parsed = {
          ...opts,
          challenge: b64urlToArrayBuffer(opts.challenge),
          user: {
            ...opts.user,
            id: b64urlToArrayBuffer(opts.user.id),
          },
        };

        if (Array.isArray(opts.excludeCredentials)) {
          parsed.excludeCredentials = opts.excludeCredentials.map((credential) => ({
            ...credential,
            id: b64urlToArrayBuffer(credential.id),
          }));
        }

        return parsed;
      };

      const parseGetOptions = (opts) => {
        if (typeof PublicKeyCredential.parseRequestOptionsFromJSON === "function") {
          return PublicKeyCredential.parseRequestOptionsFromJSON(opts);
        }

        const parsed = {
          ...opts,
          challenge: b64urlToArrayBuffer(opts.challenge),
        };

        if (Array.isArray(opts.allowCredentials)) {
          parsed.allowCredentials = opts.allowCredentials.map((credential) => ({
            ...credential,
            id: b64urlToArrayBuffer(credential.id),
          }));
        }

        return parsed;
      };

      const serializeCredential = (credential) => {
        const response = credential.response || {};
        if (method === "create") {
          return {
            id: credential.id,
            rawId: arrayBufferToB64url(credential.rawId),
            type: credential.type,
            response: {
              attestationObject: arrayBufferToB64url(response.attestationObject),
              clientDataJSON: arrayBufferToB64url(response.clientDataJSON),
            },
            clientExtensionResults: credential.getClientExtensionResults(),
          };
        }

        return {
          id: credential.id,
          rawId: arrayBufferToB64url(credential.rawId),
          type: credential.type,
          response: {
            authenticatorData: arrayBufferToB64url(response.authenticatorData),
            clientDataJSON: arrayBufferToB64url(response.clientDataJSON),
            signature: arrayBufferToB64url(response.signature),
            userHandle: response.userHandle ? arrayBufferToB64url(response.userHandle) : null,
          },
          clientExtensionResults: credential.getClientExtensionResults(),
        };
      };

      const source = { ...options };
      if (overrides.challengeOverride) source.challenge = overrides.challengeOverride;
      if (overrides.allowCredentialsOverride) source.allowCredentials = overrides.allowCredentialsOverride;

      const parsed = method === "create" ? parseCreateOptions(source) : parseGetOptions(source);
      const operation =
        method === "create"
          ? navigator.credentials.create({ publicKey: parsed })
          : navigator.credentials.get({ publicKey: parsed });

      operation
        .then((credential) => done({ ok: true, credential: serializeCredential(credential) }))
        .catch((error) => done({ ok: false, name: error.name, message: error.message }));
    JS

    result =
      page.driver.browser.execute_async_script(
        script,
        method,
        public_key_options,
        overrides,
      )
    unless result["ok"]
      raise "Browser WebAuthn failed: #{result["name"]}: #{result["message"]}"
    end

    result.fetch("credential")
  end

  def browser_json_request(method, path, payload)
    script = <<~JS
      const method = arguments[0];
      const path = arguments[1];
      const payload = arguments[2];
      const done = arguments[arguments.length - 1];

      const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || "";

      fetch(path, {
        method,
        credentials: "same-origin",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "X-XSRF-Token": csrfToken,
        },
        body: JSON.stringify(payload),
      })
        .then(async (response) => {
          const text = await response.text();
          let body;
          try {
            body = text ? JSON.parse(text) : {};
          } catch (_error) {
            body = { raw: text };
          }

          done({ status: response.status, body });
        })
        .catch((error) => done({ error: String(error) }));
    JS

    result =
      page.driver.browser.execute_async_script(script, method, path, payload)
    raise "Browser request failed: #{result["error"]}" if result["error"]

    result
  end
end
