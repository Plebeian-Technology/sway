# frozen_string_literal: true

require "rails_helper"
require "support/malformed_webauthn_credentials"

RSpec.describe SwayRelyingParty do
  # @lat: [[malformed-passkey-credential-tests#Lookup errors pass through]]
  it "lets an error raised by the stored-passkey lookup propagate unchanged" do
    client = MalformedWebauthnCredentials.client
    challenge = MalformedWebauthnCredentials.challenge
    MalformedWebauthnCredentials.enroll(client)
    assertion = MalformedWebauthnCredentials.assertion(client, challenge)

    expect {
      MalformedWebauthnCredentials.sway_relying_party.verify_authentication(assertion, challenge, user_verification: true) do
        raise NoMethodError, "lookup bug"
      end
    }.to raise_error(NoMethodError, "lookup bug")
  end

  # @lat: [[malformed-passkey-credential-tests#Decode errors after the lookup are translated]]
  it "translates a decode error raised after a successful lookup and keeps it as the cause" do
    client = MalformedWebauthnCredentials.client
    challenge = MalformedWebauthnCredentials.challenge
    enrolled = MalformedWebauthnCredentials.enroll(client)
    stored_passkey = Passkey.new(public_key: enrolled.public_key, sign_count: 0)
    corrupt = MalformedWebauthnCredentials::ASSERTION_CORRUPTIONS.fetch("a truncated authenticatorData")
    assertion = corrupt.call(MalformedWebauthnCredentials.assertion(client, challenge))

    expect {
      MalformedWebauthnCredentials.sway_relying_party.verify_authentication(assertion, challenge, user_verification: true) { stored_passkey }
    }.to raise_error(SwayRelyingParty::MalformedCredentialError) { |error| expect(error.cause).to be_a(IOError) }
  end

  # @lat: [[malformed-passkey-credential-tests#Every translated decode error is logged]]
  it "logs the original decode error as a warning before translating it" do
    client = MalformedWebauthnCredentials.client
    challenge = MalformedWebauthnCredentials.challenge
    corrupt = MalformedWebauthnCredentials::REGISTRATION_CORRUPTIONS.fetch("a truncated attestationObject")
    attestation = corrupt.call(MalformedWebauthnCredentials.registration(client, challenge))
    allow(SwayLogging).to receive(:log_exception)

    expect {
      MalformedWebauthnCredentials.sway_relying_party.verify_registration(attestation, challenge, user_verification: true)
    }.to raise_error(SwayRelyingParty::MalformedCredentialError)

    expect(SwayLogging).to have_received(:log_exception).with(
      "webauthn.malformed_credential",
      exception: kind_of(StandardError),
      level: :warn,
      ceremony: "registration"
    )
  end

  it "verifies a well-formed assertion" do
    client = MalformedWebauthnCredentials.client
    challenge = MalformedWebauthnCredentials.challenge
    enrolled = MalformedWebauthnCredentials.enroll(client)
    stored_passkey = Passkey.new(public_key: enrolled.public_key, sign_count: 0)
    assertion = MalformedWebauthnCredentials.assertion(client, challenge)

    verified, stored = MalformedWebauthnCredentials.sway_relying_party.verify_authentication(assertion, challenge, user_verification: true) { stored_passkey }

    expect(verified.sign_count).to eq(1)
    expect(stored).to be(stored_passkey)
  end
end
