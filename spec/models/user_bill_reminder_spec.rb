# frozen_string_literal: true

# == Schema Information
#
# Table name: user_bill_reminders
# Database name: primary
#
#  id         :integer          not null, primary key
#  sent_at    :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bill_id    :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_user_bill_reminders_on_bill_id  (bill_id)
#  index_user_bill_reminders_on_user_id  (user_id)
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#  user_id  (user_id => users.id)
#
require "rails_helper"

RSpec.describe UserBillReminder, type: :model do
  describe "associations" do
    it "belongs to a user" do
      record = create(:user_bill_reminder)
      expect(record.user).to be_a(User)
    end

    it "belongs to a bill" do
      record = create(:user_bill_reminder)
      expect(record.bill).to be_a(Bill)
    end
  end

  describe "validations" do
    it "is valid with a factory-built instance" do
      expect(create(:user_bill_reminder)).to be_valid
    end

    it "requires a user" do
      record = build(:user_bill_reminder, user: nil)
      expect(record.valid?).to be(false)
      expect(record.errors[:user]).to be_present
    end

    it "requires a bill" do
      record = build(:user_bill_reminder, bill: nil)
      expect(record.valid?).to be(false)
      expect(record.errors[:bill]).to be_present
    end
  end

  describe "#sent_at" do
    it "persists the sent_at timestamp" do
      at = Time.zone.parse("2026-01-01 12:00:00")
      record = create(:user_bill_reminder, sent_at: at)
      expect(record.reload.sent_at.to_i).to eq(at.to_i)
    end
  end
end
