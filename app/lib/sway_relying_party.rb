# frozen_string_literal: true

# @lat: [[malformed-passkey-credentials#An unreadable credential is an invalid credential]]
class SwayRelyingParty < WebAuthn::RelyingParty
  class MalformedCredentialError < WebAuthn::Error
    def initialize(message = "unreadable passkey response")
      super
    end
  end

  # @lat: [[malformed-passkey-credentials#Which decoding failures escape the WebAuthn gem]]
  DECODE_ERRORS = [
    ArgumentError,
    IOError,
    TypeError,
    NoMethodError,
    RuntimeError,
    JSON::ParserError,
    CBOR::UnpackError,
    COSE::Error,
    OpenSSL::OpenSSLError
  ].freeze

  def verify_registration(raw_credential, challenge, **options)
    rejecting_malformed_input(ceremony: "registration") { super }
  end

  # @lat: [[malformed-passkey-credentials#The stored-passkey lookup keeps its own errors]]
  def verify_authentication(raw_credential, challenge, **options, &lookup)
    return rejecting_malformed_input(ceremony: "authentication") { super } unless lookup

    lookup_raised = false
    guarded_lookup = proc do |credential|
      lookup_raised = true
      stored_credential = lookup.call(credential)
      lookup_raised = false
      stored_credential
    end

    rejecting_malformed_input(ceremony: "authentication", passthrough: -> { lookup_raised }) do
      super(raw_credential, challenge, **options, &guarded_lookup)
    end
  end

  private

  # @lat: [[malformed-passkey-credentials#Every refusal is logged where it is translated]]
  def rejecting_malformed_input(ceremony:, passthrough: -> { false })
    yield
  rescue *DECODE_ERRORS => error
    raise if passthrough.call

    SwayLogging.log_exception("webauthn.malformed_credential", exception: error, level: :warn, ceremony: ceremony)
    raise MalformedCredentialError
  end
end
