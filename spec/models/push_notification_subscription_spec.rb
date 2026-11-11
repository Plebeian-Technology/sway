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
#  index_push_notification_subscriptions_on_user_id_and_endpoint  (user_id,endpoint) UNIQUE
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
require "rails_helper"

RSpec.describe PushNotificationSubscription, type: :model do
  describe "associations" do
    it "belongs to a user" do
      record = create(:push_notification_subscription)
      expect(record.user).to be_a(User)
    end
  end

  describe "validations" do
    it "persists endpoint column" do
      record =
        create(
          :push_notification_subscription,
          endpoint: "https://fcm.googleapis.com/fcm/send/abc123"
        )
      expect(record.reload.endpoint).to eq(
        "https://fcm.googleapis.com/fcm/send/abc123"
      )
    end

    it "defaults subscribed to false when not explicitly set" do
      user = create(:user)
      record =
        PushNotificationSubscription.create!(
          user: user,
          endpoint: "https://example.com/sub",
          p256dh: "p",
          auth: "a"
        )
      expect(record.reload.subscribed).to be(false)
    end

    it "rejects non-HTTPS endpoints and arbitrary non-push hosts" do
      user = create(:user)

      http_sub = PushNotificationSubscription.new(
        user: user,
        endpoint: "http://fcm.googleapis.com/fcm/send/abc123",
        p256dh: "p",
        auth: "a"
      )
      expect(http_sub).not_to be_valid
      expect(http_sub.errors[:endpoint]).to be_present

      internal_sub = PushNotificationSubscription.new(
        user: user,
        endpoint: "https://internal.corp/push",
        p256dh: "p",
        auth: "a"
      )
      expect(internal_sub).not_to be_valid
      expect(internal_sub.errors[:endpoint]).to be_present

      ip_sub = PushNotificationSubscription.new(
        user: user,
        endpoint: "https://169.254.169.254/push",
        p256dh: "p",
        auth: "a"
      )
      expect(ip_sub).not_to be_valid
      expect(ip_sub.errors[:endpoint]).to be_present
    end
  end

  describe "#send_web_push_notification" do
    it "passes 5-second open_timeout and read_timeout to WebPush.payload_send" do
      record = create(
        :push_notification_subscription,
        endpoint: "https://fcm.googleapis.com/fcm/send/abc123",
        p256dh: "p256dh-key",
        auth: "auth-key"
      )
      allow(EnvSecret).to receive(:read).with("VAPID_PUBLIC_KEY").and_return("pub")
      allow(EnvSecret).to receive(:read).with("VAPID_PRIVATE_KEY").and_return("priv")

      expect(WebPush).to receive(:payload_send).with(
        hash_including(
          endpoint: "https://fcm.googleapis.com/fcm/send/abc123",
          open_timeout: 5,
          read_timeout: 5
        )
      )

      record.send_web_push_notification({title: "Hello"})
    end
  end

  describe ".active scope" do
    it "returns only subscribed subscriptions" do
      active = create(:push_notification_subscription, subscribed: true)
      create(:push_notification_subscription, subscribed: false)

      expect(PushNotificationSubscription.active).to include(active)
      expect(PushNotificationSubscription.active.count).to eq(1)
    end
  end
end
