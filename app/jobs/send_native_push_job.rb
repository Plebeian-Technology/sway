# frozen_string_literal: true

# @lat: [[device-push-token-management#Why SendNativePushJob only revokes on a real delivery receipt]]
class SendNativePushJob < ApplicationJob
  queue_as :default

  def perform(user_device_id, payload)
    device = UserDevice.find_by(id: user_device_id)
    return if device.nil?
    return unless device.revoked_at.nil?
    return if device.push_token.blank?

    kind = payload[:kind].to_s

    # @lat: [[device-push-token-management#Why SendNativePushJob only revokes on a real delivery receipt]]
    if kind == "test_push"
      return NativePushDispatcher.deliver(device, payload)
    end

    pref = device.user.notification_preferences.find_by(key: kind)
    return if pref.nil? || !pref.enabled?

    NativePushDispatcher.deliver(device, payload)
  rescue NativePushDispatcher::DeviceNotRegisteredError
    # @lat: [[device-push-token-management#Why SendNativePushJob only revokes on a real delivery receipt]]
    device&.revoke!
  end
end
