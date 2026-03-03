RSpec.shared_context "WebAuthnDouble" do
  let(:fake_challenge) { "fake-challenge" }
  let(:fake_credential_id) { "fake-credential-id" }
  let(:fake_public_key) { "fake-public-key" }

  let(:registration_options_double) do
    double(
      "RegistrationOptions",
      challenge: fake_challenge,
      as_json: {
        challenge: fake_challenge,
        rp: {
          name: "sway-test",
        },
      },
      to_json: { challenge: fake_challenge, rp: { name: "sway-test" } }.to_json,
    )
  end

  let(:authentication_options_double) do
    double(
      "AuthenticationOptions",
      challenge: fake_challenge,
      as_json: {
        challenge: fake_challenge,
        timeout: 120_000,
      },
      to_json: { challenge: fake_challenge, timeout: 120_000 }.to_json,
    )
  end

  let(:verified_registration_double) do
    double(
      "VerifiedRegistration",
      id: fake_credential_id,
      public_key: fake_public_key,
      sign_count: 0,
    )
  end

  let(:verified_authentication_double) do
    double(
      "VerifiedAuthentication",
      id: fake_credential_id,
      raw_id: Base64.strict_encode64(fake_credential_id),
      sign_count: 42,
    )
  end

  before do
    allow_any_instance_of(WebAuthn::RelyingParty).to receive(
      :options_for_registration,
    ).and_return(registration_options_double)
    allow_any_instance_of(WebAuthn::RelyingParty).to receive(
      :verify_registration,
    ).and_return(verified_registration_double)
    allow_any_instance_of(WebAuthn::RelyingParty).to receive(
      :options_for_authentication,
    ).and_return(authentication_options_double)

    allow_any_instance_of(WebAuthn::RelyingParty).to receive(
      :verify_authentication,
    ) do |_instance, _params, _challenge, user_verification:, &block|
      raise "Expected user verification" unless user_verification

      stored_passkey = block.call(verified_authentication_double)
      [verified_authentication_double, stored_passkey]
    end

    allow_any_instance_of(ApplicationController).to receive(:reset_session) do
      session_hash.clear if defined?(session_hash)
    end

    allow(RefreshToken).to receive(:for).and_return(
      instance_double(RefreshToken, as_cookie: { value: "refresh-token" }),
    )
  end
end
