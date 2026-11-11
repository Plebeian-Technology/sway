# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApplicationController
      # @lat: [[csrf-bearer-skip-design#A second layer for /api/v1]]
      protect_from_forgery with: :null_session

      # @lat: [[api-v1-base-controller-auth-gates#Why the mobile-auth helpers live here]]
      skip_before_action :is_api_request_and_is_route_api_accessible?, raise: false
      skip_before_action :authenticate_sway_user!, raise: false
      before_action :authenticate_mobile_user!, unless: :public_endpoint?

      rescue_from ActiveRecord::RecordNotFound do |e|
        render_error(code: "not_found", message: e.message.presence || "Resource not found", status: :not_found)
      end
      rescue_from ActionController::ParameterMissing do |e|
        render_error(code: "bad_request", message: e.message, status: :bad_request)
      end

      def current_user
        return @current_user if defined?(@current_user)

        @current_user = authenticate_with_api_key
      end

      protected

      def public_endpoint?
        false
      end

      def authenticate_mobile_user!
        return if current_user.present?

        render_error(code: "unauthorized", message: "Valid bearer token required", status: :unauthorized)
      end

      # @lat: [[api-v1-base-controller-auth-gates#Why the mobile-auth helpers live here]]
      def credential_for_verify(credential)
        return {} if credential.blank?
        return credential.to_unsafe_h if credential.respond_to?(:to_unsafe_h)
        credential
      end

      # @lat: [[webauthn-rp-id-settings-resolution#Why the mobile passkey callbacks log the origin the client reported]]
      def log_passkey_client_origin(credential)
        client_data = credential_for_verify(credential).with_indifferent_access.dig(:response, :clientDataJSON)
        return if client_data.blank?

        parsed = JSON.parse(Base64.urlsafe_decode64(client_data.to_s))
        SwayLogging.info(
          "webauthn.client_data " \
          "origin=#{parsed["origin"].inspect} " \
          "type=#{parsed["type"].inspect} " \
          "android_package_name=#{parsed["androidPackageName"].inspect} " \
          "request_host=#{request.host}"
        )
      rescue ArgumentError, TypeError, JSON::ParserError => e
        SwayLogging.warn("webauthn.client_data.unreadable error_class=#{e.class}")
      end

      def build_bearer_token_payload(user, platform: nil)
        plat = platform.presence_in(UserDevice::PLATFORMS) || "ios"
        device = UserDevice.create!(
          user: user,
          platform: plat,
          last_seen_at: Time.current,
          app_version: request.headers["X-App-Version"]
        )
        raw = SecureRandom.hex(32)
        key = ApiKey.create!(
          bearer: user,
          user_device: device,
          token: raw,
          expires_at: 90.days.from_now,
          name: "mobile-#{plat}-#{device.id}"
        )

        {
          bearer_token: raw,
          device_id: device.id,
          user: user.to_sway_json,
          expires_at: key.expires_at&.iso8601
        }
      end
    end
  end
end
