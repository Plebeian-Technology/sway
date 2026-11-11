# frozen_string_literal: true

module Api
  module V1
    # @lat: [[test-push-device-targeting#Why the request body carries push_token]]
    class NotificationsController < BaseController
      rate_limit to: 10, within: 5.minutes,
        by: -> { current_user&.id || Digest::SHA256.hexdigest(request.headers["Authorization"].to_s) },
        only: :test_push,
        with: -> { render_error(code: "rate_limited", message: "Too many test sends", status: :too_many_requests) },
        store: ApplicationController::RATE_LIMIT_STORE

      def test_push
        token = params[:push_token].to_s
        if token.blank?
          return render_error(
            code: "missing_push_token",
            message: "push_token is required so the test push targets the calling device.",
            status: :unprocessable_content
          )
        end

        device = current_user.user_devices.with_push.find_by(push_token: token)
        unless device
          # @lat: [[test-push-device-targeting#Why NotificationPrefsScreen test mocks DeviceRegistrationContext]]
          return render_error(
            code: "no_device",
            message: "This device is not registered for push on this account.",
            status: :not_found
          )
        end

        SendNativePushJob.perform_later(device.id, {
          title: "Test Notification",
          body: "Sway push notifications are working.",
          kind: "test_push"
        })

        render json: {sent: true}
      end
    end
  end
end
