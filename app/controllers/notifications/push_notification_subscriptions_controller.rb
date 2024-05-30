# typed: true

class Notifications::PushNotificationSubscriptionsController < ApplicationController
  extend T::Sig

  before_action :set_subscription

  def create
    if @subscription.present?
      @subscription.update!(subscribed: true) unless @subscription.subscribed

      SwayPushNotificationService.new(
        title: 'Notifications Activated',
        body: "We'll send you one of these when a new Bill of the Week is released."
      ).send_push_notification

      render json: @subscription.attributes, status: :ok
    else
      render json: PushNotificationSubscription.create!(
        **push_notification_subscription_params,
        user: current_user,
        subscribed: true
      ).attributes, status: :ok
    end
  end

  def destroy
    return unless @subscription.present?

    @subscription.update!(subscribed: false)
    render json: @subscription.attributes, status: :ok
  end

  private

  def set_subscription
    @subscription = current_user&.push_notification_subscriptions&.filter { |s| s.endpoint == push_notification_subscription_params[:endpoint] }
  end

  def push_notification_subscription_params
    params.require(:push_notification_subscription).permit(
      :endpoint,
      :p256dh,
      :auth
    )
  end
end
