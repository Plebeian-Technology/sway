# typed: true

class SwayPushNotificationService
  extend T::Sig

  ICON = 'sway-us-light.png'

  def initialize(subscription = nil, title:, body:)
    @title = title
    @body = body
    @subscription = subscription
  end

  def send_push_notification
    if subscriptions.is_a?(Array)
      subscriptions.each do |sub|
        sent = send_web_push_notification(sub)
        Rails.logger.info "Sent webpush to - #{sub.endpoint}" unless Rails.env.production?
      end
    else

      subscriptions.find_each do |sub|
        sent = send_web_push_notification(sub)
        Rails.logger.info "Sent webpush to - #{sub.endpoint}" unless Rails.env.production?
      end
    end
  end

  private

  def message
    @message ||= {
      title: @title,
      body: @body,
      icon:
    }
  end

  def icon
    ActionController::Base.helpers.image_url(ICON)
  end

  def vapid
    @vapid ||= {
      subject: 'mailto:legis@sway.vote',
      public_key: ENV['VAPID_PUBLIC_KEY'],
      private_key: ENV['VAPID_PRIVATE_KEY']
    }
  end

  def send_web_push_notification(subscription)
    WebPush.payload_send(
      message: JSON.generate(message),
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh,
      auth: subscription.auth,
      urgency: 'high', # optional, it can be very-low, low, normal, high, defaults to normal
      vapid:
    )
  end

  def subscriptions
    @subscriptions ||= get_subscriptions
  end

  def get_subscriptions
    return [@subscription] if @subscription

    PushNotificationSubscription.active
  end
end
