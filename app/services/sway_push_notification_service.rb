# frozen_string_literal: true
# typed: true

class SwayPushNotificationService
  extend T::Sig

  ICON = "sway-us-light.png"

  def initialize(subscription = nil, title:, body:)
    @title = title
    @body = body
    @subscription = subscription
  end

  def send_push_notification
    Rails.logger.info("Sending push notifications.")
    subscriptions.send(iterator) do |sub|
      sub.send_web_push_notification(message)
      unless Rails.env.production?
        Rails.logger.info "Sent webpush to - #{sub.endpoint}"
      end
    end
  end

  private

  def iterator
    subscriptions.is_a?(Array) ? :each : :find_each
  end

  def message
    @message ||= { title: @title, body: @body, icon: }
  end

  def icon
    ActionController::Base.helpers.image_url(ICON)
  end

  def subscriptions
    @subscriptions ||= get_subscriptions
  end

  def get_subscriptions
    return [@subscription] if @subscription

    PushNotificationSubscription.active
  end
end
