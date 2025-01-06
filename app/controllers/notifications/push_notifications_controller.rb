# frozen_string_literal: true
# typed: true

module Notifications
  class PushNotificationsController < ApplicationController
    extend T::Sig

    before_action :set_subscription

    # Allow the user to test a push notification
    def create
      SwayPushNotificationService.new(
        @subscription,
        title: "Notifications Test",
        body: "Test Web Push Notification."
      ).send_push_notification

      render json: {success: true, message: "Push Notification Sent"}, status: :ok
    end

    private

    def set_subscription
      @subscription = current_user&.push_notification_subscriptions&.find do |s|
        s.endpoint == push_notification_subscription_params[:endpoint]
      end
    end

    def push_notification_subscription_params
      params.require(:push_notification).permit(
        :endpoint
      )
    end
  end
end
