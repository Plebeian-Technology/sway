# frozen_string_literal: true

class SwayPushNotificationService
  ICON = "/images/sway-us-light.png"

  def initialize(subscription = nil, title:, body:, url: nil, subscriptions: nil)
    @title = title
    @body = body
    @url = url
    @subscription = subscription
    @subscriptions = subscriptions
  end

  def send_push_notification
    SwayLogging.info("Sending push notifications.")
    subscriptions.send(iterator) do |sub|
      sub.send_web_push_notification(message)
      unless Rails.env.production?
        SwayLogging.info "Sent webpush to - #{sub.endpoint}"
      end
    end
  end

  private

  def iterator
    subscriptions.is_a?(Array) ? :each : :find_each
  end

  def message
    # @lat: [[organization-notification-delivery#Web push deep-link payload shape]]
    @message ||= {title: @title, body: @body, icon:, data: (@url ? {url: @url} : nil)}.compact
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
