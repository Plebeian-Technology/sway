# frozen_string_literal: true
# typed: true

# == Schema Information
#
# Table name: push_notification_subscriptions
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
  extend T::Sig

  belongs_to :user

  scope :active, -> { where(subscribed: true) }

  sig { params(message: T::Hash[String, T.untyped]).returns(T.untyped) }
  def send_web_push_notification(message)
    WebPush.payload_send(
      message: JSON.generate(message),
      endpoint:,
      p256dh:,
      auth:,
      urgency: "high", # optional, it can be very-low, low, normal, high, defaults to normal
      vapid:
    )
  rescue Exception => e # rubocop:disable Lint/RescueException
    Rails.logger.error(e)
  end

  private

  def vapid
    @vapid ||= {
      subject: "mailto:legis@sway.vote",
      public_key: ENV["VAPID_PUBLIC_KEY"],
      private_key: ENV["VAPID_PRIVATE_KEY"]
    }
  end
end
