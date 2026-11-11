# frozen_string_literal: true

# @lat: [[native-push-clients-design#Why FcmClient never logs the push token]]
class NativePushDispatcher
  class DeviceNotRegisteredError < StandardError; end

  def self.deliver(device, payload)
    title = payload[:title].to_s
    body = payload[:body].to_s
    data = payload[:data] || {}

    case device.platform.to_s
    when "android"
      FcmClient.deliver(push_token: device.push_token, title: title, body: body, data: data)
    when "ios"
      ApnsClient.deliver(device_token: device.push_token, title: title, body: body, data: data)
    else
      raise ArgumentError, "unknown platform: #{device.platform.inspect}"
    end
  rescue FcmClient::DeviceNotRegisteredError, ApnsClient::DeviceNotRegisteredError
    raise DeviceNotRegisteredError
  end
end
