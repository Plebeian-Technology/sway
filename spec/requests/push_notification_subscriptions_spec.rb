require "rails_helper"

RSpec.describe "Notifications::PushNotificationSubscriptions", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:user) { setup.last }
  let(:subscription_params) do
    {
      endpoint: "https://example.com/endpoint",
      p256dh: "test_p256dh",
      auth: "test_auth"
    }
  end

  before { sign_in user }

  # @lat: [[push-subscriptions#Why subscription redirects name the Push tab explicitly]]
  describe "the tab a subscription change returns to" do
    it "names the Push tab when enabling" do
      post notifications_push_notification_subscriptions_path,
        params: {push_notification_subscription: subscription_params}

      expect(URI.parse(response.location).query).to eq("tab=push")
    end

    it "names the Push tab when disabling" do
      delete notifications_destroy_push_notification_subscription_path,
        params: {push_notification_subscription: subscription_params}

      expect(URI.parse(response.location).query).to eq("tab=push")
    end
  end

  describe "POST /notifications/push_notification_subscriptions" do
    context "when subscription does not exist" do
      it "creates a new subscription and redirects to notifications" do
        expect do
          post notifications_push_notification_subscriptions_path,
            params: {
              push_notification_subscription: subscription_params
            }
        end.to change(PushNotificationSubscription, :count).by(1)

        expect(response).to redirect_to(notifications_path(tab: "push"))
        expect(flash[:notice]).to eq("Push notifications enabled.")
        subscription =
          PushNotificationSubscription.find_by(
            endpoint: subscription_params[:endpoint]
          )
        expect(subscription).not_to be_nil
        expect(subscription.subscribed).to be true
      end
    end

    context "when subscription already exists and is unsubscribed" do
      it "updates the subscription to subscribed and sends activation notification" do
        push_service = instance_double(SwayPushNotificationService, send_push_notification: nil)
        expect(push_service).to receive(:send_push_notification)

        subscription =
          create(
            :push_notification_subscription,
            user: user,
            endpoint: subscription_params[:endpoint],
            p256dh: subscription_params[:p256dh],
            auth: subscription_params[:auth],
            subscribed: false
          )

        expect(SwayPushNotificationService).to receive(:new).with(
          subscription,
          title: "Notifications Activated",
          body: "We'll send you one of these when a new Bill of the Month is released."
        ).and_return(push_service)

        expect do
          post notifications_push_notification_subscriptions_path,
            params: {
              push_notification_subscription: subscription_params
            }
        end.not_to change(PushNotificationSubscription, :count)

        expect(response).to redirect_to(notifications_path(tab: "push"))
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
            subscribed: true
          )

        expect do
          post notifications_push_notification_subscriptions_path,
            params: {
              push_notification_subscription: subscription_params
            }
        end.not_to change(PushNotificationSubscription, :count)

        expect(response).to redirect_to(notifications_path(tab: "push"))
        expect(subscription.reload.subscribed).to be true
      end
    end

    describe "activation confirmation recipient isolation" do
      let(:other_user) { create(:user) }
      let!(:other_user_sub) do
        create(
          :push_notification_subscription,
          user: other_user,
          endpoint: "https://example.com/other-user-endpoint",
          subscribed: true
        )
      end
      let!(:requester_second_sub) do
        create(
          :push_notification_subscription,
          user: user,
          endpoint: "https://example.com/user-second-endpoint",
          subscribed: true
        )
      end

      before do
        @delivered_recipients = []
        allow_any_instance_of(PushNotificationSubscription)
          .to receive(:send_web_push_notification) do |instance, message|
            @delivered_recipients << {
              subscription_id: instance.id,
              user_id: instance.user_id,
              endpoint: instance.endpoint,
              message: message
            }
          end
      end

      it "delivers confirmation strictly to the requesting endpoint when re-enabling a disabled subscription" do
        subscription =
          create(
            :push_notification_subscription,
            user: user,
            endpoint: subscription_params[:endpoint],
            p256dh: subscription_params[:p256dh],
            auth: subscription_params[:auth],
            subscribed: false
          )

        post notifications_push_notification_subscriptions_path,
          params: {
            push_notification_subscription: subscription_params
          }

        expect(response).to redirect_to(notifications_path(tab: "push"))
        expect(subscription.reload.subscribed).to be true
        expect(subscription.user).to eq(user)

        expect(@delivered_recipients.pluck(:endpoint)).to eq([subscription_params[:endpoint]])
        expect(@delivered_recipients.pluck(:subscription_id)).to eq([subscription.id])
        expect(@delivered_recipients.pluck(:user_id)).to eq([user.id])
      end

      it "delivers confirmation strictly to the requesting endpoint when reposting an already enabled subscription" do
        subscription =
          create(
            :push_notification_subscription,
            user: user,
            endpoint: subscription_params[:endpoint],
            p256dh: subscription_params[:p256dh],
            auth: subscription_params[:auth],
            subscribed: true
          )

        post notifications_push_notification_subscriptions_path,
          params: {
            push_notification_subscription: subscription_params
          }

        expect(response).to redirect_to(notifications_path(tab: "push"))
        expect(subscription.reload.subscribed).to be true

        expect(@delivered_recipients.pluck(:endpoint)).to eq([subscription_params[:endpoint]])
        expect(@delivered_recipients.pluck(:subscription_id)).to eq([subscription.id])
        expect(@delivered_recipients.pluck(:user_id)).to eq([user.id])
      end

      it "does not notify another user when posting an endpoint URL owned by that other user" do
        post notifications_push_notification_subscriptions_path,
          params: {
            push_notification_subscription: {
              endpoint: "https://example.com/other-user-endpoint",
              p256dh: "key-foreign",
              auth: "auth-foreign"
            }
          }

        expect(response).to redirect_to(notifications_path(tab: "push"))
        expect(@delivered_recipients.pluck(:user_id)).not_to include(other_user.id)
      end
    end
  end

  # Looking the row up in Ruby and then creating it races when someone clicks
  # Enable twice at once: both requests fail to find a row and both insert one.
  # A unique index on (user_id, endpoint) makes the database the referee. The
  # controller catches RecordNotUnique and settles on the row that won.
  describe "unique (user_id, endpoint) index" do
    it "rejects a duplicate (user_id, endpoint) row at the database level" do
      PushNotificationSubscription.create!(user: user, endpoint: "https://push.example/x", subscribed: true)

      expect {
        PushNotificationSubscription.create!(user: user, endpoint: "https://push.example/x", subscribed: true)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "resolves a create race to a single subscribed row (RecordNotUnique rescued)" do
      # Act out the race: a row already exists, but the controller's Ruby-side
      # lookup misses it, exactly as both simultaneous requests would, so the
      # create! branch runs and hits the unique index.
      existing = create(:push_notification_subscription,
        user: user, endpoint: subscription_params[:endpoint], subscribed: false)
      allow_any_instance_of(Notifications::PushNotificationSubscriptionsController)
        .to receive(:subscription).and_return(nil)

      expect {
        post notifications_push_notification_subscriptions_path,
          params: {push_notification_subscription: subscription_params}
      }.not_to change(PushNotificationSubscription, :count)

      expect(response).to redirect_to(notifications_path(tab: "push"))
      expect(flash[:notice]).to eq("Push notifications enabled.")
      expect(existing.reload.subscribed).to be(true)
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
            subscribed: true
          )

        delete notifications_destroy_push_notification_subscription_path,
          params: {
            push_notification_subscription: subscription_params
          }

        expect(response).to redirect_to(notifications_path(tab: "push"))
        expect(flash[:notice]).to eq("Push notifications disabled.")
        expect(subscription.reload.subscribed).to be false
      end
    end

    context "when subscription does not exist" do
      it "redirects to notifications and does nothing" do
        expect do
          delete notifications_destroy_push_notification_subscription_path,
            params: {
              push_notification_subscription: subscription_params
            }
        end.not_to change(PushNotificationSubscription, :count)

        expect(response).to redirect_to(notifications_path(tab: "push"))
      end
    end
  end
end
