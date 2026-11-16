# frozen_string_literal: true

module WebauthnSystemHelpers
  def register_passkey_user(phone:)
    start_session =
      browser_json_request("POST", users_webauthn_sessions_path, {phone:})
    # Every phone number answers 200 with a {flow:} body, so the status code
    # cannot reveal whether an account exists; a new number gets the sms flow.
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
    callback =
      browser_json_request(
        "POST",
        callback_users_webauthn_registration_index_path,
        credential.merge("passkey_label" => "System Test Passkey")
      )
    # On success the WebAuthn registration callback redirects to
    # sway_registration_index_path instead of rendering, the usual Inertia
    # pattern. This fetch is told not to follow redirects, so that shows up as
    # status 303.
    expect(callback.fetch("status")).to eq(303)

    User.find_by!(phone:)
  end

  # @lat: [[identity-and-access#A user holds one address]]
  def set_user_address(user, address)
    UserAddress.find_or_initialize_by(user: user).update!(address: address)
    address
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
      allowCredentialsOverride: allow_credentials_override
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
        overrides
      )
    unless result["ok"]
      raise "Browser WebAuthn failed: #{result["name"]}: #{result["message"]}"
    end

    result.fetch("credential")
  end

  def reject_next_passkey_creation
    page.execute_script(<<~JS)
      (() => {
        const credentials = navigator.credentials;
        const hadOwn = Object.prototype.hasOwnProperty.call(credentials, "create");
        const original = credentials.create;
        Object.defineProperty(credentials, "create", {
          configurable: true,
          writable: true,
          value: () => {
            if (hadOwn) {
              credentials.create = original;
            } else {
              delete credentials.create;
            }
            return Promise.reject(
              new DOMException("The operation either timed out or was not allowed.", "NotAllowedError")
            );
          }
        });
      })();
    JS
    nil
  end
end

RSpec.configure { |config| config.include WebauthnSystemHelpers, type: :system }
