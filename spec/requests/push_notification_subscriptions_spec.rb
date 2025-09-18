require "rails_helper"

RSpec.describe "Notifications::PushNotificationSubscriptions", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:user) { setup.last }
  let(:subscription_params) do
    {
      endpoint: "https://example.com/endpoint",
      p256dh: "test_p256dh",
      auth: "test_auth",
    }
  end

  before { sign_in user }

  describe "POST /notifications/push_notification_subscriptions" do
    context "when subscription does not exist" do
      it "creates a new subscription and returns it" do
        expect {
          post notifications_push_notification_subscriptions_path,
               params: {
                 push_notification_subscription: subscription_params,
               }
        }.to change(PushNotificationSubscription, :count).by(1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["endpoint"]).to eq(subscription_params[:endpoint])
        expect(json["subscribed"]).to be true
      end
    end

    context "when subscription already exists and is unsubscribed" do
      it "updates the subscription to subscribed" do
        subscription =
          create(
            :push_notification_subscription,
            user: user,
            endpoint: subscription_params[:endpoint],
            p256dh: subscription_params[:p256dh],
            auth: subscription_params[:auth],
            subscribed: false,
          )

        expect {
          post notifications_push_notification_subscriptions_path,
               params: {
                 push_notification_subscription: subscription_params,
               }
        }.not_to change(PushNotificationSubscription, :count)

        expect(response).to have_http_status(:ok)
        expect(subscription.reload.subscribed).to be true
      end
    end

    context "when subscription already exists and is already subscribed" do
      it "does not change the subscription" do
        subscription =
          create(
            :push_notification_subscription,
            user: user,
            endpoint: subscription_params[:endpoint],
            p256dh: subscription_params[:p256dh],
            auth: subscription_params[:auth],
            subscribed: true,
          )

        expect {
          post notifications_push_notification_subscriptions_path,
               params: {
                 push_notification_subscription: subscription_params,
               }
        }.not_to change(PushNotificationSubscription, :count)

        expect(response).to have_http_status(:ok)
        expect(subscription.reload.subscribed).to be true
      end
    end
  end

  describe "DELETE /notifications/push_notification_subscriptions" do
    context "when subscription exists" do
      it "unsubscribes the subscription" do
        subscription =
          create(
            :push_notification_subscription,
            user: user,
            endpoint: subscription_params[:endpoint],
            p256dh: subscription_params[:p256dh],
            auth: subscription_params[:auth],
            subscribed: true,
          )

        post destroy_notifications_push_notification_subscriptions_path,
             params: {
               push_notification_subscription: subscription_params,
             }

        expect(response).to have_http_status(:ok)
        expect(subscription.reload.subscribed).to be false
      end
    end

    context "when subscription does not exist" do
      it "returns ok and does nothing" do
        expect {
          post destroy_notifications_push_notification_subscriptions_path,
               params: {
                 push_notification_subscription: subscription_params,
               }
        }.not_to change(PushNotificationSubscription, :count)

        expect(response).to have_http_status(:no_content)
      end
    end
  end
end
