require "rails_helper"

RSpec.describe OnBillBecomesBotwNotifyUsersJob, type: :job do
    context "a bill already exists" do
        it "is not notifyable because the scheduled_release_date_utc has passed" do
            bill = create(:bill, scheduled_release_date_utc: Time.zone.now - 3.days)
            expect(bill.notifyable?).to eql(false)
        end

        it "is not notifyable because scheduled_release_date_utc is in the future" do
            bill = create(:bill, scheduled_release_date_utc: Time.zone.now + 3.days)
            expect(bill.notifyable?).to eql(false)
        end

        it "is not notifyable because it already has a BillNotification" do
            bill = create(:bill, scheduled_release_date_utc: Time.zone.now)
            expect(bill.notifyable?).to eql(true)
            BillNotification.create!(bill:)
            expect(bill.notifyable?).to eql(false)
        end

        it "is notifyable" do
            bill = create(:bill, scheduled_release_date_utc: Time.zone.now)
            expect(bill.notifyable?).to eql(true)
        end
    end

    context "a user has a push notification subscription" do
        include_context "Setup"

        it "sends a notification when a BillNotification is created" do
            notifier = class_double("WebPush").as_stubbed_const(transfer_nested_constants: true)
            expect(notifier).to receive(:payload_send) # to

            _sway_locale, user = setup
            PushNotificationSubscription.create!(endpoint: "taco", p256dh: "taco", auth: "taco", user: user, subscribed: true)

            bill = create(:bill, scheduled_release_date_utc: Time.zone.now)
            BillNotification.create!(bill:)
        end

        it "does NOT send a notification, when a BillNotification is NOT created" do
            notifier = class_double("WebPush").as_stubbed_const(transfer_nested_constants: true)
            expect(notifier).to_not receive(:payload_send) # to_not

            _sway_locale, user = setup
            PushNotificationSubscription.create!(endpoint: "taco", p256dh: "taco", auth: "taco", user: user, subscribed: true)

            create(:bill, scheduled_release_date_utc: Time.zone.now)
            # BillNotification.create!(bill:)
        end
    end
end
