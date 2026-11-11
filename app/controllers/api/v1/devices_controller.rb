# frozen_string_literal: true

module Api
  module V1
    class DevicesController < BaseController
      # @lat: [[device-push-token-management#Why the rate limit hashes the bearer token]]
      rate_limit to: 30, within: 1.minute,
        by: -> { Digest::SHA256.hexdigest(request.headers["Authorization"].to_s) },
        only: :update_push_token,
        if: -> { RateLimitConfig.enabled?(:device_push_token) },
        with: -> { render_error(code: "rate_limited", message: "Too many device updates", status: :too_many_requests) },
        store: ApplicationController::RATE_LIMIT_STORE

      def update_push_token
        # @lat: [[device-push-token-management#Why push token updates prefer the bearer token's bound device]]
        device =
          current_api_key&.user_device&.then { |d| d if d.revoked_at.nil? } ||
          current_user.user_devices.active.order(last_seen_at: :desc).first
        unless device
          return render_error(
            code: "no_active_device",
            message: "No active device for current user",
            status: :not_found
          )
        end

        token = params.require(:push_token)

        # @lat: [[device-push-token-management#Why another user's device is revoked when a push token moves]]
        UserDevice.transaction do
          UserDevice.where(push_token: token, revoked_at: nil)
            .where.not(id: device.id)
            .update_all(revoked_at: Time.current)

          device.update!(
            push_token: token,
            platform: params[:platform].presence || device.platform,
            app_version: params[:app_version].presence || device.app_version,
            last_seen_at: Time.current
          )
        end

        render json: {
          id: device.id,
          push_token: device.push_token,
          platform: device.platform,
          app_version: device.app_version,
          last_seen_at: device.last_seen_at.iso8601
        }
      end

      def destroy
        device = current_user.user_devices.find_by(id: params[:id])
        unless device
          return render_error(
            code: "not_found",
            message: "Device not found",
            status: :not_found
          )
        end

        device.revoke!
        head :no_content
      end
    end
  end
end
