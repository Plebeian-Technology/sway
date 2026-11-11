# frozen_string_literal: true

# @lat: [[device-push-token-management#Why CleanupRevokedDevicesJob exists as a safety net, not the primary path]]
class CleanupRevokedDevicesJob < ApplicationJob
  queue_as :background

  def perform
    UserDevice
      .active
      .joins(:api_keys)
      .where("api_keys.expires_at < ?", Time.current)
      .distinct
      .find_each do |device|
        device.revoke!
      end
  end
end
