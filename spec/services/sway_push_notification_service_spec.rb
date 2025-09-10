# typed: true
# frozen_string_literal: true

RSpec.describe SwayPushNotificationService do
    describe "#send_push_notification" do
        before { PushNotificationSubscription.destroy_all }

        it "sends a push notification to a passed subscription" do
            subscription = create(:push_notification_subscription)
            sub_spy = spy(subscription)

            SwayPushNotificationService.new(sub_spy, title: "Hello from RSpec", body: "A body.").send_push_notification

            expect(sub_spy).to have_received(:send_web_push_notification)
        end

        it "sends a push notification to all active subscriptions" do
            create(:push_notification_subscription)

            allow(WebPush).to receive(:payload_send)

            SwayPushNotificationService.new(title: "Hello from RSpec", body: "A body.").send_push_notification

            expect(WebPush).to have_received(:payload_send)
        end

        it "does not send a push notification because all subscriptions are inactive" do
            create(:push_notification_subscription, subscribed: false)

            allow(WebPush).to receive(:payload_send)

            SwayPushNotificationService.new(title: "Hello from RSpec", body: "A body.").send_push_notification

            expect(WebPush).to_not have_received(:payload_send)
        end
    end
end
