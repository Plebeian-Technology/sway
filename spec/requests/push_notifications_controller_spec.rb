require "rails_helper"

RSpec.describe "Notifications::PushNotifications", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:user) { setup.last }
  let(:endpoint) { "https://example.com/endpoint" }
  let(:subscription) do
    create(
      :push_notification_subscription,
      user: user,
      endpoint: endpoint,
      subscribed: true,
    )
  end

  before { sign_in user }

  describe "POST /notifications/push_notifications" do
    context "when the subscription exists" do
      it "sends a test notification and returns success" do
        subscription # ensure subscription is created

        expect(SwayPushNotificationService).to receive(:new).with(
          subscription,
          title: "Notifications Test",
          body: "Test Web Push Notification.",
        ).and_call_original

        post notifications_push_notifications_path,
             params: {
               push_notification: {
                 endpoint: endpoint,
               },
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to eq(true)
        expect(json["message"]).to include("Test notification sent")
      end
    end

    context "when the subscription does not exist" do
      it "returns failure and a helpful message" do
        post notifications_push_notifications_path,
             params: {
               push_notification: {
                 endpoint: "https://notfound.com/endpoint",
               },
             }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to eq(false)
        expect(json["message"]).to include("Failed to send test notification")
      end
    end
  end
end
