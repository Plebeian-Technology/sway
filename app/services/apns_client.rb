# frozen_string_literal: true

require "apnotic"
require "stringio"

# @lat: [[native-push-clients-design#Why ApnsClient keeps one connection pool per thread]]
class ApnsClient
  class DeviceNotRegisteredError < StandardError; end
  class ApnsError < StandardError; end

  APNS_HOSTS = {
    "production" => "https://api.push.apple.com:443",
    "development" => "https://api.sandbox.push.apple.com:443"
  }.freeze

  POOL_THREAD_KEY = :apns_pool_instance

  def self.deliver(device_token:, title:, body:, data: {})
    cfg = Rails.application.config.apns
    return nil unless cfg.enabled

    pool = Thread.current[POOL_THREAD_KEY] ||= build_connection_pool(cfg)

    notification = Apnotic::Notification.new(device_token)
    notification.alert = {title: title, body: body}
    notification.topic = cfg.bundle_id
    notification.custom_payload = data.transform_keys(&:to_s) if data.any?

    pool.with do |connection|
      response = connection.push(notification)
      raise ApnsError, "APNs timeout (no response)" unless response
      return true if response.ok?

      empty_body = {}
      # @type var empty_body: Hash[String, untyped]
      parsed_body = begin
        JSON.parse(response.body)
      rescue
        empty_body
      end
      reason = parsed_body["reason"]
      raise DeviceNotRegisteredError if %w[Unregistered BadDeviceToken].include?(reason)

      raise ApnsError, "APNs #{response.status} #{reason}"
    end
  end

  def self.build_connection_pool(cfg)
    Apnotic::ConnectionPool.new(
      {
        auth_method: :token,
        cert_path: StringIO.new(cfg.auth_key_p8),
        key_id: cfg.key_id,
        team_id: cfg.team_id,
        url: APNS_HOSTS.fetch(cfg.env, APNS_HOSTS["development"])
      },
      size: 1
    )
  end
end
