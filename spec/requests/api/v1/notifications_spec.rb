# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Notifications", type: :request do
  include ActiveJob::TestHelper

  describe "POST /api/v1/notifications/test_push" do
    let!(:user) { create(:user) }

    it "returns 401 unauthorized without bearer" do
      post "/api/v1/notifications/test_push",
        params: {push_token: "anything"},
        as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json_body.dig(:error, :code)).to eq("unauthorized")
    end

    it "returns 422 missing_push_token when body omits push_token" do
      headers = authenticate_as(user)

      post "/api/v1/notifications/test_push",
        params: {},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body.dig(:error, :code)).to eq("missing_push_token")
    end

    it "returns 404 no_device when token does not match any device of current_user" do
      headers = authenticate_as(user)

      post "/api/v1/notifications/test_push",
        params: {push_token: "no-such-token"},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:not_found)
      expect(json_body.dig(:error, :code)).to eq("no_device")
    end

    it "returns 404 no_device when token belongs to ANOTHER user (T-37-04-01)" do
      other_user = create(:user)
      create(:user_device, user: other_user, push_token: "OTHER_USER_TOKEN", platform: "ios")

      headers = authenticate_as(user)

      post "/api/v1/notifications/test_push",
        params: {push_token: "OTHER_USER_TOKEN"},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:not_found)
      expect(json_body.dig(:error, :code)).to eq("no_device")
    end

    it "delivers test push end-to-end via perform_enqueued_jobs even when ALL prefs are disabled (HIGH 3c)" do
      # The bearer's device is the calling device. Set its push_token so the request body matches.
      headers = authenticate_as(user)
      device = user.user_devices.active.order(last_seen_at: :desc).first
      device.update!(push_token: "calling-token", last_seen_at: Time.current)

      # Turn every notification preference off, so the test really proves the bypass runs.
      NotificationPreference::KEYS.each do |k|
        user.notification_preferences.find_or_create_by!(key: k).update!(enabled: false)
      end

      # Fake only the very last step: the HTTP call out to Apple's or Google's push service.
      dispatcher_calls = [] #: Array[[Integer, Hash[Symbol, untyped]]]
      allow(NativePushDispatcher).to receive(:deliver) { |dev, payload|
        dispatcher_calls << [dev.id, payload]
        true
      }

      perform_enqueued_jobs do
        post "/api/v1/notifications/test_push",
          params: {push_token: "calling-token"},
          headers: headers,
          as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(json_body).to eq({sent: true})
      expect(dispatcher_calls.length).to eq(1)
      expect(dispatcher_calls.first.first).to eq(device.id)
      expect(dispatcher_calls.first.last[:kind]).to eq("test_push")
      expect(dispatcher_calls.first.last[:title]).to eq("Test Notification")
    end
  end
end
