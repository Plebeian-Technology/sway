# frozen_string_literal: true

require "rails_helper"

# @lat: [[notification-delivery-browser-coverage#The system example covers the notification flow]]
RSpec.describe "Notification Delivery Flow", type: :system, js: true do
  include_context "TwilioDouble"
  include ActiveJob::TestHelper

  let(:sway_locale) do
    SwayLocale.find_by(
      city: "baltimore",
      state: "MD",
      country: "United States"
    ) ||
      create(
        :sway_locale,
        city: "baltimore",
        state: "MD",
        country: "United States"
      )
  end
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }

  before do
    @signed_in_user =
      create(:user,
        phone: "4105550099",
        is_phone_verified: true)
    # User#before_create forces is_phone_verified back to false no matter what
    # .create was given, so write the column directly afterwards. The SMS
    # send-out only picks up users whose phone is verified.
    @signed_in_user.update_columns(is_phone_verified: true)
    address =
      create(
        :address,
        city: "baltimore",
        region_code: "MD",
        country: "United States"
      )
    create(:user_address, user: @signed_in_user, address: address)
    # This user_legislator link is now the only thing that tells the SMS
    # send-out which locale a user belongs to; the user_districts table is gone.
    create(:user_legislator, user: @signed_in_user, legislator: legislator)
    @signed_in_user.complete!
    ActiveJob::Base.queue_adapter = :test
  end

  it "user enables push + SMS, then BillNotification fan-out enqueues SmsDeliveryJob" do
    sign_in_as(@signed_in_user)

    # Install the fake service worker (spec/support/service_worker_stub.rb)
    # BEFORE visiting /notifications, so React finds it when the page sets up.
    endpoint = "https://fcm.googleapis.com/fcm/send/TEST-DELIVERY-#{SecureRandom.hex(4)}"
    inject_service_worker_stub!(endpoint: endpoint)

    # Steps 1-3 — turn on push notifications
    visit "/notifications"
    expect(page).to have_button("Enable push notifications on this device", wait: 10)
    click_button("Enable push notifications on this device")

    # The subscription is saved: the form posts to
    # push_notification_subscriptions#create.
    expect(page).to have_button("Disable on this device", wait: 10)
    expect(
      PushNotificationSubscription.where(user: @signed_in_user).count
    ).to be >= 1

    # Step 4 — turn on SMS. The consent checkbox sits on the phone/SMS tab of
    # /notifications, inside the [data-testid='notification-sms-toggle']
    # element. Push and SMS live on separate tabs, so go straight to
    # /notifications?tab=sms to land on the SMS panel.
    visit "/notifications?tab=sms"

    within("[data-testid='notification-sms-toggle']") do
      # @lat: [[sms-consent-copy-verbatim#Why a checkbox and not a toggle]]
      find("#sms-notifications-enabled[role='checkbox']").click
      click_button "Save preferences"
    end

    # @lat: [[notification-delivery-browser-coverage#Saving preferences is confirmed at both boundaries]]
    expect(page).to have_text("Notification preferences updated.", wait: 10)
    expect(@signed_in_user.reload.sms_notifications_enabled).to be true

    # @lat: [[notification-delivery-browser-coverage#The example invokes the delivery service after consent]]
    bill = create(
      :bill,
      :bill_of_the_month,
      sway_locale: sway_locale,
      legislator: legislator
    )

    expect do
      SmsNotificationService.send_bill_of_the_month_notification(bill)
    end.to have_enqueued_job(SmsDeliveryJob).at_least(:once)
  end
end
