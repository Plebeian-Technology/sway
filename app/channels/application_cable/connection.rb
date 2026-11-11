# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      user = user_from_session || user_from_refresh_token || user_from_bearer_token
      user || reject_unauthorized_connection
    end

    def user_from_session
      session = request.session
      user_id = session[:user_id]
      user = User.find_by(id: user_id) if user_id
      return nil if user.nil?
      return nil if session[:auth_identity].present? && session[:auth_identity].to_i != user.created_at.to_i

      user
    end

    # @lat: [[identity-and-access#Sessions, cookies and bearer tokens#Refresh tokens bind to their issuing request]]
    def user_from_refresh_token
      token = cookies.encrypted[:refresh_token]
      return if token.blank?

      refresh_token = RefreshToken.find_by(token: token)
      return unless refresh_token&.usable_for?(request)

      refresh_token.user
    end

    def user_from_bearer_token
      raw_token = request.params[:token].to_s
      return if raw_token.blank?

      api_key = ApiKey.authenticate_by_token(raw_token)
      return if api_key.nil?

      bearer = api_key.bearer
      bearer if bearer.is_a?(User)
    rescue ApiKey::MissingHmacSecretError
      nil
    end
  end
end
