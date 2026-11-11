# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmsNotificationService do
  let(:user) do
    # A before_create hook sets both flags to false, so opt in afterwards.
    u =
      create(
        :user,
        phone: "1234567890",
        is_phone_verified: true,
        sms_notifications_enabled: true
      )
    u.update!(is_phone_verified: true, sms_notifications_enabled: true)
    u
  end
  let(:sway_locale) { create(:sway_locale, city: "test_city", state: "maryland", country: "united_states") }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) { create(:bill, sway_locale: sway_locale, title: "Test Bill") }

  # Sets up locale membership the way registration does: an ACTIVE
  # user_legislator whose district sits in the bill's locale. Registration
  # creates only UserLegislator rows, never UserDistrict.
  before do
    create(:user_legislator, user: user, legislator: legislator, active: true)
  end

  describe ".send_bill_of_the_month_notification" do
    it "enqueues SMS for a user who registered via SwayRegistrationService (active user_legislators only)" do
      expect(SmsDeliveryJob).to receive(:perform_later).with(
        to: user.phone,
        body: include("New Bill of the Month in Test City: Test Bill")
      )

      described_class.send_bill_of_the_month_notification(bill)
    end

    it "does not enqueue SMS for opted-out users" do
      user.update(sms_notifications_enabled: false)
      expect(SmsDeliveryJob).not_to receive(:perform_later)
      described_class.send_bill_of_the_month_notification(bill)
    end

    it "does not enqueue SMS for a user whose only user_legislator in the locale is inactive" do
      inactive_user =
        create(
          :user,
          phone: "1234567891",
          is_phone_verified: true,
          sms_notifications_enabled: true
        )
      inactive_user.update!(is_phone_verified: true, sms_notifications_enabled: true)
      create(
        :user_legislator,
        user: inactive_user,
        legislator: legislator,
        active: false
      )

      expect(SmsDeliveryJob).to receive(:perform_later).with(
        to: user.phone,
        body: include("New Bill of the Month in Test City: Test Bill")
      )
      expect(SmsDeliveryJob).not_to receive(:perform_later).with(
        to: inactive_user.phone,
        body: anything
      )

      described_class.send_bill_of_the_month_notification(bill)
    end
  end

  describe ".send_voting_reminder" do
    it "enqueues a reminder SMS job" do
      expect(SmsDeliveryJob).to receive(:perform_later).with(
        to: user.phone,
        body: include("Sway: You haven't voted on the featured bill")
      )

      described_class.send_voting_reminder(user, bill)
    end
  end

  # A stored Baltimore title runs to hundreds of characters, so what reaches a
  # text message is the headline the browser already shows.
  context "a bill whose stored title carries the legislature's own wording" do
    let(:bill) do
      create(
        :bill,
        sway_locale: sway_locale,
        title: "Zoning Code – Modifications FOR the purpose of amending provisions of the Baltimore City Zoning Code"
      )
    end

    it "sends the Bill of the Month alert with the title's headline alone" do
      expect(SmsDeliveryJob).to receive(:perform_later).with(
        to: user.phone,
        body: "New Bill of the Month in Test City: Zoning Code. Check it out on Sway!"
      )

      described_class.send_bill_of_the_month_notification(bill)
    end

    it "sends the voting reminder with the title's headline alone" do
      expect(SmsDeliveryJob).to receive(:perform_later).with(
        to: user.phone,
        body: "Sway: You haven't voted on the featured bill in Test City: Zoning Code. Vote now!"
      )

      described_class.send_voting_reminder(user, bill)
    end
  end

  describe "SmsDeliveryJob failure path" do
    it "propagates enqueue errors from SmsDeliveryJob to the caller" do
      allow(SmsDeliveryJob).to receive(:perform_later).and_raise(
        ActiveJob::EnqueueError.new("queue unavailable")
      )

      expect {
        described_class.send_bill_of_the_month_notification(bill)
      }.to raise_error(ActiveJob::EnqueueError)
    end
  end

  # @lat: [[sms-notification-service-design#Why recipient selection resolves through active legislator links]]
  describe "recipient filtering and deduplication" do
    it "excludes unverified phones, other-locale users, and deduplicates users with multiple active legislators in the same locale" do
      district_2 = create(:district, sway_locale: sway_locale, name: "MD2")
      legislator_2 = create(:legislator, sway_locale: sway_locale, district: district_2)
      create(:user_legislator, user: user, legislator: legislator_2, active: true)

      unverified = create(:user, phone: "4105550191", sms_notifications_enabled: true, is_phone_verified: false)
      create(:user_legislator, user: unverified, legislator: legislator, active: true)

      other_locale = create(:sway_locale)
      other_district = create(:district, sway_locale: other_locale)
      other_legislator = create(:legislator, sway_locale: other_locale, district: other_district)
      other_user = create(:user, phone: "4105550192", sms_notifications_enabled: true, is_phone_verified: true)
      create(:user_legislator, user: other_user, legislator: other_legislator, active: true)

      expect(SmsDeliveryJob).to receive(:perform_later).with(
        to: user.phone,
        body: anything
      ).once

      described_class.send_bill_of_the_month_notification(bill)
    end
  end
end
