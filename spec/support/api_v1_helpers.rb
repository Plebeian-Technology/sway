# frozen_string_literal: true

# Helpers for request specs that hit /api/v1.
module ApiV1Helpers
  def authenticate_as(user, platform: "ios")
    device = UserDevice.create!(
      user: user,
      platform: platform,
      last_seen_at: Time.current,
      app_version: "1.0.0"
    )
    raw = SecureRandom.hex(32)
    ApiKey.create!(
      bearer: user,
      user_device: device,
      token: raw,
      expires_at: 90.days.from_now,
      name: "test-#{raw[0, 8]}"
    )
    {"Authorization" => "Bearer #{raw}"}
  end

  def json_body
    JSON.parse(response.body, symbolize_names: true)
  end

  def expect_error_envelope(code:, status: nil)
    expect(response).to have_http_status(status) if status
    expect(json_body).to match(hash_including(error: hash_including(code: code)))
  end
end

RSpec.configure do |c|
  c.include ApiV1Helpers, type: :request
end
