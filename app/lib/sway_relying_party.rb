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
    rejecting_malformed_input { super }
  end

  # @lat: [[malformed-passkey-credentials#The stored-passkey lookup keeps its own errors]]
  def verify_authentication(raw_credential, challenge, **options, &lookup)
    return rejecting_malformed_input { super } unless lookup

    lookup_raised = false
    guarded_lookup = proc do |credential|
      lookup_raised = true
      stored_credential = lookup.call(credential)
      lookup_raised = false
      stored_credential
    end

    rejecting_malformed_input(passthrough: -> { lookup_raised }) do
      super(raw_credential, challenge, **options, &guarded_lookup)
    end
  end

  private

  def rejecting_malformed_input(passthrough: -> { false })
    yield
  rescue *DECODE_ERRORS
    raise if passthrough.call

    raise MalformedCredentialError
  end
end
