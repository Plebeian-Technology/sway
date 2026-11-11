# @lat: [[sway-logging-design#Why filter_parameters lists :anthropic_api_key alongside the :_key substring matcher]]
Rails.application.config.filter_parameters += %i[
  passw
  secret
  token
  _key
  crypt
  salt
  certificate
  otp
  ssn
  phone
  email
  passkey
  push_token
  bearer_token
  sms_verified_token
  credential
  challenge
  webauthn_challenge
  anthropic_api_key
  street
  postal_code
  latitude
  longitude
  full_name
]

Rails.application.config.filter_parameters << /\Acode\z/i
# @lat: [[websocket-token-log-scrubbing#Why the Claude API key gets a second, pattern-based filter]]
Rails.application.config.filter_parameters << /sk-ant-[A-Za-z0-9_-]+/

# @lat: [[websocket-token-log-scrubbing#Why the WebSocket URL gets its own log scrubbing]]
module ActionCableTokenScrubbing
  TOKEN_IN_QUERY = %r{(/cable\?[^"'\s]*?token=)[^&"'\s]+}i
  REPLACEMENT = '\1[FILTERED]'

  def call(severity, time, progname, msg)
    scrubbed = msg.is_a?(String) ? msg.gsub(TOKEN_IN_QUERY, REPLACEMENT) : msg
    super(severity, time, progname, scrubbed)
  end
end

Rails.logger&.formatter&.singleton_class&.prepend(ActionCableTokenScrubbing)
