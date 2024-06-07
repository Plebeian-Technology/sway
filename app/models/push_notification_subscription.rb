# typed: true

# == Schema Information
#
# Table name: push_notification_subscriptions
#
#  id         :integer          not null, primary key
#  user_id    :integer          not null
#  endpoint   :string
#  p256dh     :string
#  auth       :string
#  subscribed :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class PushNotificationSubscription < ApplicationRecord
  extend T::Sig

  belongs_to :user

  scope :active, -> { where(subscribed: true) }

  sig { params(message: T::Hash[String, T.untyped]).returns(T.untyped) }
  def send_web_push_notification(message)
    WebPush.payload_send(
      message: JSON.generate(message),
      endpoint: self.endpoint,
      p256dh: self.p256dh,
      auth: self.auth,
      urgency: 'high', # optional, it can be very-low, low, normal, high, defaults to normal
      vapid:
    )
  end

  private

  def vapid
    @vapid ||= {
      subject: 'mailto:legis@sway.vote',
      public_key: ENV['VAPID_PUBLIC_KEY'],
      private_key: ENV['VAPID_PRIVATE_KEY']
    }
  end
end
