# frozen_string_literal: true

require "webauthn/fake_client"

# @lat: [[scoping-spec-helper-types#Scope spec helper types]]
module MalformedWebauthnCredentials
  ORIGIN = "http://www.example.com"
  RP_ID = "www.example.com"
  PHONE = "4105557100"
  WEB_REJECTION_MESSAGE = "Verification failed: unreadable passkey response"

  REGISTRATION_CORRUPTIONS = {
    "a truncated attestationObject" => lambda { |credential|
      bytes = MalformedWebauthnCredentials.decode(credential.dig("response", "attestationObject"))
      MalformedWebauthnCredentials.replace(credential, %w[response attestationObject], MalformedWebauthnCredentials.encode(bytes.byteslice(0, 40).to_s))
    },
    "an attestationObject of invalid CBOR" => lambda { |credential|
      MalformedWebauthnCredentials.replace(credential, %w[response attestationObject], MalformedWebauthnCredentials.encode("\xff\x00garbage".b))
    },
    "an attestationObject that is not base64url" => lambda { |credential|
      MalformedWebauthnCredentials.replace(credential, %w[response attestationObject], "!!not-base64!!")
    },
    "an attestationObject sent as a number" => lambda { |credential|
      MalformedWebauthnCredentials.replace(credential, %w[response attestationObject], 12_345)
    },
    "a credential without rawId or response" => lambda { |credential|
      credential.slice("id", "type")
    }
  }.freeze

  ASSERTION_CORRUPTIONS = {
    "a truncated authenticatorData" => lambda { |credential|
      bytes = MalformedWebauthnCredentials.decode(credential.dig("response", "authenticatorData"))
      MalformedWebauthnCredentials.replace(credential, %w[response authenticatorData], MalformedWebauthnCredentials.encode(bytes.byteslice(0, 20).to_s))
    },
    "an authenticatorData whose extensions are invalid CBOR" => lambda { |credential|
      bytes = MalformedWebauthnCredentials.decode(credential.dig("response", "authenticatorData"))
      flags = bytes.getbyte(32).to_i | 0x80
      corrupted = bytes.byteslice(0, 32).to_s + [flags].pack("C") + bytes.byteslice(33, 4).to_s + "\xff\x00".b
      MalformedWebauthnCredentials.replace(credential, %w[response authenticatorData], MalformedWebauthnCredentials.encode(corrupted))
    },
    "a signature that is not base64url" => lambda { |credential|
      MalformedWebauthnCredentials.replace(credential, %w[response signature], "!!not-base64!!")
    },
    "an authenticatorData sent as a number" => lambda { |credential|
      MalformedWebauthnCredentials.replace(credential, %w[response authenticatorData], 12_345)
    },
    "a credential without rawId or response" => lambda { |credential|
      credential.slice("id", "type")
    }
  }.freeze

  def self.challenge
    encode(SecureRandom.random_bytes(32))
  end

  def self.client
    WebAuthn::FakeClient.new(ORIGIN)
  end

  def self.registration(client, challenge)
    client.create(challenge: challenge, rp_id: RP_ID, user_verified: true)
  end

  def self.assertion(client, challenge)
    client.get(challenge: challenge, rp_id: RP_ID, user_verified: true, sign_count: 1)
  end

  def self.sway_relying_party
    SwayRelyingParty.new(allowed_origins: [ORIGIN], id: RP_ID, name: "sway-test")
  end

  def self.enroll(client)
    enrollment_challenge = challenge
    WebAuthn::RelyingParty
      .new(allowed_origins: [ORIGIN], id: RP_ID, name: "sway-test")
      .verify_registration(registration(client, enrollment_challenge), enrollment_challenge, user_verification: true)
  end

  def self.enroll_user(client)
    enrolled = enroll(client)
    user = FactoryBot.create(:user, :registered, phone: PHONE)
    FactoryBot.create(:passkey, user: user, external_id: enrolled.id, public_key: enrolled.public_key)
    user
  end

  def self.replace(credential, path, value)
    copy = JSON.parse(JSON.generate(credential))
    *parents, field = path
    parents.reduce(copy) { |node, key| node.fetch(key) }[field] = value
    copy
  end

  def self.encode(bytes)
    Base64.urlsafe_encode64(bytes, padding: false)
  end

  def self.decode(text)
    Base64.urlsafe_decode64(text)
  end
end
