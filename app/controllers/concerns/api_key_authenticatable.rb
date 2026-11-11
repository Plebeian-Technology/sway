module ApiKeyAuthenticatable
  extend ActiveSupport::Concern

  include ActionController::HttpAuthentication::Basic::ControllerMethods
  include ActionController::HttpAuthentication::Token::ControllerMethods

  attr_reader :current_api_key, :current_bearer

  def authenticate_with_api_key!
    return @current_bearer if defined?(@api_key_authenticated) && @current_bearer.present?

    if defined?(@api_key_authenticated) && @current_bearer.nil?
      request_http_token_authentication
      return nil
    end

    result = authenticate_or_request_with_http_token do |http_token, options|
      @current_bearer = authenticator(http_token, options)
    end
    @api_key_authenticated = true
    result
  end

  def authenticate_with_api_key
    return @current_bearer if defined?(@api_key_authenticated)

    @api_key_authenticated = true
    authenticate_with_http_token do |http_token, options|
      @current_bearer = authenticator(http_token, options)
    end
  end

  def token_credential_supplied?
    return false unless respond_to?(:request) && request.present?

    auth = request.headers["Authorization"].presence || (request.respond_to?(:authorization) ? request.authorization : nil)
    return false if auth.blank?

    auth.to_s.strip.match?(/\A(Bearer|Token)\b/i)
  end

  private

  attr_writer :current_api_key, :current_bearer

  def authenticator(http_token, _options)
    # @lat: [[api-key-hmac-secret-handling#Why token authentication never queries the raw token against the digest column]]
    @current_api_key = ApiKey.authenticate_by_token(http_token)

    @current_api_key&.update(last_used_on_utc: Time.zone.now)

    current_api_key&.bearer
  end
end
