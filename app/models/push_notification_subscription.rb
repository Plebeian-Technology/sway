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
  belongs_to :user

  scope :active, -> { where(subscribed: true) }
end
