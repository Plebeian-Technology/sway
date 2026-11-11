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
      subscribed: true
    )
  end

  before { sign_in user }

  describe "POST /notifications/push_notifications" do
    context "when the subscription exists" do
      it "sends a test notification and redirects to notifications" do
        subscription # ensure subscription is created

        push_service = instance_double(SwayPushNotificationService)
        allow(push_service).to receive(:send_push_notification)
        expect(SwayPushNotificationService).to receive(:new).with(
          subscription,
          title: "Notifications Test",
          body: "Test Web Push Notification."
        ).and_return(push_service)

        post notifications_push_notifications_path,
          params: {
            push_notification: {
              endpoint: endpoint
            }
          }

        expect(response).to redirect_to(notifications_path)
        expect(flash[:notice]).to include("Test notification sent")
      end
    end

    context "when the subscription does not exist" do
      it "sets an alert flash and redirects to notifications" do
        post notifications_push_notifications_path,
          params: {
            push_notification: {
              endpoint: "https://notfound.com/endpoint"
            }
          }

        expect(response).to redirect_to(notifications_path)
        expect(flash[:alert]).to include("Failed to send test notification")
      end
    end

    it "rate-limits repeated test push notification requests per IP" do
      memory_store = ActiveSupport::Cache::MemoryStore.new
      ApplicationController::RATE_LIMIT_STORE.backend = memory_store
      begin
        10.times do
          post notifications_push_notifications_path,
            params: {push_notification: {endpoint: "https://notfound.com/endpoint"}},
            headers: {"REMOTE_ADDR" => "198.51.100.77"}
          expect(response).to redirect_to(notifications_path)
        end

        post notifications_push_notifications_path,
          params: {push_notification: {endpoint: "https://notfound.com/endpoint"}},
          headers: {"REMOTE_ADDR" => "198.51.100.77"}
        expect(response).to have_http_status(:too_many_requests)
      ensure
        ApplicationController::RATE_LIMIT_STORE.backend = ActiveSupport::Cache::NullStore.new
      end
    end
  end
end
