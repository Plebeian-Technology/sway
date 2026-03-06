# frozen_string_literal: true

# == Schema Information
#
# Table name: push_notification_subscriptions
# Database name: primary
#
#  id         :integer          not null, primary key
#  auth       :string
#  endpoint   :string
#  p256dh     :string
#  subscribed :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_push_notification_subscriptions_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class PushNotificationSubscription < ApplicationRecord
  belongs_to :user

  scope :active, -> { where(subscribed: true) }

  def send_web_push_notification(message)
    endpoint_value = endpoint
    p256dh_value = p256dh
    auth_value = auth
    vapid_value = vapid

    return if endpoint_value.nil? || p256dh_value.nil? || auth_value.nil?
    private_key = vapid_value[:private_key]
    public_key = vapid_value[:public_key]
    subject = vapid_value[:subject]

    return if private_key.nil? || public_key.nil? || subject.nil?

    WebPush.payload_send(
      message: JSON.generate(message),
      endpoint: endpoint_value,
      p256dh: p256dh_value,
      auth: auth_value,
      urgency: "high", # optional, it can be very-low, low, normal, high, defaults to normal
      vapid: {
        private_key:,
        public_key:,
        subject:,
      },
    )
  rescue Exception => e # rubocop:disable Lint/RescueException
    Rails.logger.error(e)
  end

  private

  def vapid
    @vapid ||= {
      subject: "mailto:legis@sway.vote",
      public_key: ENV["VAPID_PUBLIC_KEY"],
      private_key: ENV["VAPID_PRIVATE_KEY"],
    }
  end
end
