# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmsNotificationService do
  let(:user) do
    u =
      create(
        :user,
        phone: "1234567890",
        is_phone_verified: true,
        sms_notifications_enabled: true,
      )
    u.update!(is_phone_verified: true, sms_notifications_enabled: true)
    u
  end
  let(:sway_locale) { create(:sway_locale, city: "test_city") }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:bill) { create(:bill, sway_locale: sway_locale, title: "Test Bill") }

  before { create(:user_district, user: user, district: district) }

  describe ".send_bill_of_the_week_notification" do
    it "enqueues SMS jobs for opted-in users" do
      expect(SmsDeliveryJob).to receive(:perform_later).with(
        to: user.phone,
        body: include("New Bill of the Week in Test City: Test Bill"),
      )

      described_class.send_bill_of_the_week_notification(bill)
    end

    it "does not enqueue SMS for opted-out users" do
      user.update(sms_notifications_enabled: false)
      expect(SmsDeliveryJob).not_to receive(:perform_later)
      described_class.send_bill_of_the_week_notification(bill)
    end
  end

  describe ".send_voting_reminder" do
    it "enqueues a reminder SMS job" do
      expect(SmsDeliveryJob).to receive(:perform_later).with(
        to: user.phone,
        body: include("Reminder: You haven't voted"),
      )

      described_class.send_voting_reminder(user, bill)
    end
  end
end
