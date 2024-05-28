# typed: true

class SwayPushNotificationService
  extend T::Sig

  ICON = 'sway-us-light.png'

  def initialize(title:, body:)
    @title = title
    @body = body
  end

  def send_push_notification
    PushNotificationSubscription.active.find_each do |subscription|
      send_web_push_notification(subscription)
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
      subject: "mailto:legis@sway.vote",
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
      vapid:
    )
  end
end
