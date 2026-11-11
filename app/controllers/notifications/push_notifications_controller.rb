# frozen_string_literal: true

module Notifications
  class PushNotificationsController < ApplicationController
    rate_limit to: 10, within: 1.minute,
      name: "push_notifications",
      by: -> { request.remote_ip },
      only: :create,
      store: ApplicationController::RATE_LIMIT_STORE

    before_action :set_subscription

    def create
      if @subscription.nil?
        flash[
          :alert
        ] = "Failed to send test notification. Try disabling and re-enabling notifications."
      else
        SwayPushNotificationService.new(
          @subscription,
          title: "Notifications Test",
          body: "Test Web Push Notification."
        ).send_push_notification

        flash[
          :notice
        ] = "Test notification sent. You should receive one soon. Check your browser's or device's notification permissions if you don't receive it."
      end
      redirect_to notifications_path
    end

    private

    def set_subscription
      @subscription =
        current_user&.push_notification_subscriptions&.find do |s|
          s.endpoint == push_notification_subscription_params[:endpoint]
        end
    end

    def push_notification_subscription_params
      params.require(:push_notification).permit(:endpoint)
    end
  end
end
