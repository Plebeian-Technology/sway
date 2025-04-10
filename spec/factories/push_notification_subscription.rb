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
FactoryBot.define do
  factory :push_notification_subscription do
    user
    endpoint { Faker::Internet.url(host: "sway.vote", path: "/whatever", scheme: "https") }
    p256dh { Faker::String.random(length: 20) }
    auth { Faker::String.random(length: 20) }
    subscribed { true }

    initialize_with do
      new({
        endpoint:,
        p256dh:,
        auth:,
        subscribed:
      })
    end
  end
end
