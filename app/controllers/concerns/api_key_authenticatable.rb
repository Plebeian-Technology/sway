# typed: true

# https://keygen.sh/blog/how-to-implement-api-key-authentication-in-rails-without-devise/

module ApiKeyAuthenticatable
    extend ActiveSupport::Concern
    extend T::Sig

    include ActionController::HttpAuthentication::Basic::ControllerMethods
    include ActionController::HttpAuthentication::Token::ControllerMethods

    attr_reader :current_api_key, :current_bearer

    # Use this to raise an error and automatically respond with a 401 HTTP status
    # code when API key authentication fails
    # https://stackoverflow.com/a/34982438/6410635
    # https://keygen.sh/blog/how-to-implement-api-key-authentication-in-rails-without-devise/
    def authenticate_with_api_key!
        authenticate_or_request_with_http_token do |http_token, options|
            @current_bearer = authenticator(http_token, options)
        end
    end

    # Use this for optional API key authentication
    def authenticate_with_api_key
        authenticate_with_http_token { |http_token, options| @current_bearer = authenticator(http_token, options) }
    end

    private

    attr_writer :current_api_key, :current_bearer

    def authenticator(http_token, _options)
        @current_api_key = ApiKey.find_by(token_digest: http_token)
        @current_api_key = ApiKey.authenticate_by_token(http_token)

        @current_api_key&.update(last_used_on_utc: Time.zone.now)

        current_api_key&.bearer
    end
end
