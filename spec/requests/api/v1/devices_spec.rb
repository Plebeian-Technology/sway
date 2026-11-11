# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Devices", type: :request do
  let!(:user) { create(:user) }

  describe "PATCH /api/v1/devices/push_token" do
    it "upserts push_token on the user's most-recently-active device" do
      headers = authenticate_as(user)
      device = user.user_devices.active.first
      expect(device).to be_present

      patch "/api/v1/devices/push_token",
        params: {push_token: "FCM:abc123", platform: "ios", app_version: "1.2.3"},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)
      device.reload
      expect(device.push_token).to eq("FCM:abc123")
      expect(device.app_version).to eq("1.2.3")
    end

    it "returns 401 unauthorized without bearer" do
      patch "/api/v1/devices/push_token",
        params: {push_token: "FCM:abc"},
        as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "transfers an active push_token from a prior user's device on the same physical device" do
      prior_device = create(:user_device, push_token: "APNs:shared-token", last_seen_at: 1.day.ago)

      headers = authenticate_as(user)
      device = user.user_devices.active.first

      patch "/api/v1/devices/push_token",
        params: {push_token: "APNs:shared-token", platform: "ios", app_version: "1.2.3"},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)

      device.reload
      prior_device.reload

      expect(device.push_token).to eq("APNs:shared-token")
      expect(device.revoked_at).to be_nil
      expect(prior_device.revoked_at).to be_present
    end

    it "updates the UserDevice bound to the calling Bearer token even when another device has a newer last_seen_at" do
      headers = authenticate_as(user, platform: "ios")
      device_a = user.user_devices.active.first
      device_a.update!(last_seen_at: 2.hours.ago, push_token: "APNs:device-a-old")

      device_b = create(:user_device, user: user, platform: "android", last_seen_at: 1.minute.ago, push_token: "FCM:device-b")

      patch "/api/v1/devices/push_token",
        params: {push_token: "APNs:device-a-new", platform: "ios", app_version: "2.0.0"},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)
      expect(json_body[:id]).to eq(device_a.id)
      expect(device_a.reload.push_token).to eq("APNs:device-a-new")
      expect(device_a.revoked_at).to be_nil
      expect(device_b.reload.push_token).to eq("FCM:device-b")
      expect(device_b.revoked_at).to be_nil
    end
  end

  describe "DELETE /api/v1/devices/:id" do
    it "revokes the device and cascades expiry to its ApiKey" do
      headers = authenticate_as(user)
      device = user.user_devices.active.first
      key = device.api_keys.first
      expect(device.revoked_at).to be_nil

      delete "/api/v1/devices/#{device.id}", headers: headers, as: :json
      expect(response).to have_http_status(:no_content)

      device.reload
      key.reload
      expect(device.revoked_at).to be_present
      expect(key.expires_at).to be <= Time.current
    end

    it "returns 404 for a device not owned by current_user" do
      other = create(:user_device)
      headers = authenticate_as(user)
      delete "/api/v1/devices/#{other.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(json_body.dig(:error, :code)).to eq("not_found")
    end
  end
end
