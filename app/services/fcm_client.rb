# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "stringio"

# @lat: [[native-push-clients-design#Why FcmClient never logs the push token]]
class FcmClient
  class DeviceNotRegisteredError < StandardError; end
  class FcmError < StandardError; end

  FCM_OAUTH_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

  # @lat: [[native-push-clients-design#Why FcmClient caches its OAuth token in process memory, not Rails.cache]]
  TOKEN_MUTEX = Thread::Mutex.new

  def self.deliver(push_token:, title:, body:, data: {})
    cfg = Rails.application.config.fcm
    return nil unless cfg.enabled

    token = oauth2_token(cfg.service_account_json)
    uri = URI("https://fcm.googleapis.com/v1/projects/#{cfg.project_id}/messages:send")
    payload = {
      message: {
        token: push_token,
        notification: {title: title, body: body},
        data: data.transform_values(&:to_s)
      }
    }
    req = Net::HTTP::Post.new(
      uri,
      "Authorization" => "Bearer #{token}",
      "Content-Type" => "application/json"
    )
    req.body = payload.to_json
    res = Net::HTTP.start(
      uri.host.to_s, uri.port,
      use_ssl: true, open_timeout: 5, read_timeout: 10
    ) { |h| h.request(req) }
    return JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)

    empty_body = {}
    # @type var empty_body: Hash[String, untyped]
    parsed = begin
      JSON.parse(res.body)
    rescue
      empty_body
    end
    status = parsed.dig("error", "details")&.first&.dig("errorCode") ||
      parsed.dig("error", "status")
    raise DeviceNotRegisteredError if %w[UNREGISTERED NOT_FOUND].include?(status)

    raise FcmError, "FCM #{status}: #{res.body}"
  end

  # @lat: [[native-push-clients-design#Why FcmClient caches its OAuth token in process memory, not Rails.cache]]
  def self.oauth2_token(sa_json)
    TOKEN_MUTEX.synchronize do
      cached = @oauth2_token
      expires_at = @cached_until
      if cached.nil? || expires_at.nil? || Time.current >= expires_at
        cached = fetch_oauth2_token(sa_json)
        @oauth2_token = cached
        @cached_until = 45.minutes.from_now
      end
      cached
    end
  end

  def self.fetch_oauth2_token(sa_json)
    require "googleauth"
    creds = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(sa_json),
      scope: FCM_OAUTH_SCOPE
    )
    creds.fetch_access_token!["access_token"]
  end
end
