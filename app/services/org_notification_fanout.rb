# frozen_string_literal: true

# @lat: [[organization-notification-delivery#Fan-out batches users and checks the master preference]]
class OrgNotificationFanout
  def self.deliver(user:, title:, body:, url:)
    PushNotificationSubscription.active.where(user_id: user.id).find_each do |sub|
      SwayPushNotificationService.new(sub, title: title, body: body, url: url)
        .send_push_notification
    end

    user.user_devices.active.find_each do |device|
      SendNativePushJob.perform_later(
        device.id,
        {kind: "org_position_taken", title: title, body: body, data: {url: url}}
      )
    end

    if user.sms_notifications_enabled? && user.is_phone_verified?
      SmsDeliveryJob.perform_later(to: user.phone, body: "#{title}: #{body}")
    end
  end
end
