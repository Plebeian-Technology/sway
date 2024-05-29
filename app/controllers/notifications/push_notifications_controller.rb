# typed: true

class Notifications::PushNotificationsController < ApplicationController
  extend T::Sig

  before_action :verify_is_admin, :set_subscription

  def create
    SwayPushNotificationService.new(
      @subscription,
      title: 'Notifications Test',
      body: 'Test Web Push Notification.'
    ).send_push_notification

    render json: { success: true, message: 'Push Notification Sent' }, status: :ok
  end

  private

  def set_subscription
    @subscription = current_user&.push_notification_subscriptions&.find { |s| s.endpoint == push_notification_subscription_params[:endpoint] }
  end

  def push_notification_subscription_params
    params.require(:push_notification).permit(
      :endpoint
    )
  end
end
