# frozen_string_literal: true

module Notifications
  class PushNotificationSubscriptionsController < ApplicationController
    def create
      if subscription.present?
        subscription.update!(subscribed: true) unless subscription.subscribed

        # @lat: [[push-subscriptions#Why activation confirmations target only the requesting subscription]]
        SwayPushNotificationService.new(
          subscription,
          title: "Notifications Activated",
          body:
            "We'll send you one of these when a new Bill of the Month is released."
        ).send_push_notification

      else
        PushNotificationSubscription.create!(
          **push_notification_subscription_params,
          user: current_user,
          subscribed: true
        )
      end
      flash[:notice] = "Push notifications enabled."
      redirect_to notifications_path(tab: NotificationsController::PUSH_TAB)
    rescue ActiveRecord::RecordNotUnique
      # @lat: [[push-subscriptions#Why concurrent subscription creates recover from RecordNotUnique]]
      current_user
        &.push_notification_subscriptions
        &.find_by(endpoint: push_notification_subscription_params[:endpoint])
        &.update!(subscribed: true)
      flash[:notice] = "Push notifications enabled."
      redirect_to notifications_path(tab: NotificationsController::PUSH_TAB)
    rescue ActiveRecord::RecordInvalid => e
      flash[:alert] = "Failed to enable push notifications: #{e.message}"
      redirect_to notifications_path(tab: NotificationsController::PUSH_TAB)
    end

    def destroy
      sub =
        current_user&.push_notification_subscriptions&.find do |s|
          s.endpoint == push_notification_subscription_params[:endpoint]
        end
      sub&.update!(subscribed: false)
      flash[:notice] = "Push notifications disabled."
      redirect_to notifications_path(tab: NotificationsController::PUSH_TAB)
    end

    private

    def subscription
      @subscription ||=
        current_user&.push_notification_subscriptions&.find do |s|
          s.endpoint == push_notification_subscription_params[:endpoint]
        end
    end

    def push_notification_subscription_params
      params.require(:push_notification_subscription).permit(
        :endpoint,
        :p256dh,
        :auth
      )
    end
  end
end
