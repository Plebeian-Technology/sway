# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_notifications
# Database name: primary
#
#  id         :integer          not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bill_id    :integer          not null
#
# Indexes
#
#  index_bill_notifications_on_bill_id  (bill_id) UNIQUE
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#
require "rails_helper"

RSpec.describe BillNotification, type: :model do
  describe "associations" do
    it "belongs to a bill" do
      record = create(:bill_notification)
      expect(record.bill).to be_a(Bill)
    end
  end

  describe "validations" do
    it "is valid with a factory-built instance" do
      expect(build(:bill_notification, bill: create(:bill))).to be_valid
    end

    it "requires a bill to persist" do
      record = BillNotification.new
      expect(record.valid?).to be(false)
      expect(record.errors[:bill]).to be_present
    end
  end

  describe "the web push it sends" do
    it "carries the title's headline rather than the stored title" do
      bill = create(:bill, title: "Zoning Code – Modifications FOR the purpose of amending provisions")
      sent = nil
      allow(SwayPushNotificationService).to receive(:new) do |**kwargs|
        sent = kwargs
        instance_double(SwayPushNotificationService, send_push_notification: nil)
      end

      create(:bill_notification, bill: bill)

      expect(sent).to include(
        title: "New Bill of the Month",
        body: "#{bill.sway_locale.city_name}: Zoning Code",
        url: "/bills/#{bill.id}"
      )
    end
  end

  describe "#bill accessor" do
    it "returns the associated Bill" do
      bill = create(:bill)
      record = create(:bill_notification, bill: bill)
      expect(record.bill).to eq(bill)
    end
  end

  describe "#notify error resilience" do
    it "logs and suppresses StandardError and ActiveJob::EnqueueError from SMS and web push delivery" do
      bill = create(:bill)
      push_service = instance_double(SwayPushNotificationService, send_push_notification: nil)
      allow(SwayPushNotificationService).to receive(:new).and_return(push_service)
      allow(SmsNotificationService).to receive(:send_bill_of_the_month_notification).and_raise(StandardError.new("SMS failure"))

      expect(SwayLogging).to receive(:log_exception).with("bill_notification.notify_failed", hash_including(bill_id: bill.id))

      record = described_class.create!(bill: bill)
      expect(record).to be_persisted
    end
  end
end
