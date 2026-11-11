# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: user_bill_shares
# Database name: primary
#
#  id          :integer          not null, primary key
#  redeemed_at :datetime
#  share_uuid  :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  bill_id     :integer          not null
#  user_id     :integer          not null
#
# Indexes
#
#  index_user_bill_shares_on_bill_id              (bill_id)
#  index_user_bill_shares_on_share_uuid           (share_uuid) UNIQUE
#  index_user_bill_shares_on_user_id_and_bill_id  (user_id,bill_id) UNIQUE
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#  user_id  (user_id => users.id)
#
RSpec.describe UserBillShare, type: :model do
  describe "associations" do
    it "belongs to a user and a bill" do
      share = create(:user_bill_share)
      expect(share.user).to be_a(User)
      expect(share.bill).to be_a(Bill)
    end
  end

  describe "share_uuid" do
    it "auto-generates a unique share_uuid before validation on create" do
      share = create(:user_bill_share)
      expect(share.share_uuid).to be_present
      expect(share.share_uuid).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "generates distinct UUIDs for different shares" do
      first = create(:user_bill_share)
      second = create(:user_bill_share)
      expect(first.share_uuid).not_to eq(second.share_uuid)
    end

    it "replaces a blank share_uuid with a generated UUID before validation on create" do
      share = create(:user_bill_share, share_uuid: "")
      expect(share.share_uuid).to match(/\A[0-9a-f-]{36}\z/)
    end
  end

  describe "validations" do
    it "validates uniqueness of bill_id scoped to user_id" do
      existing = create(:user_bill_share)
      duplicate = build(:user_bill_share, user: existing.user, bill: existing.bill)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:bill_id]).to include("has already been taken")
    end
  end

  describe "#share_path" do
    it "returns the redemption path with the share_uuid" do
      share = create(:user_bill_share)
      expect(share.share_path).to eq("/bill_shares/#{share.share_uuid}")
    end
  end

  describe ".redeemed" do
    it "returns only records where redeemed_at is present" do
      unredeemed = create(:user_bill_share, redeemed_at: nil)
      redeemed = create(:user_bill_share, :redeemed)

      results = described_class.redeemed
      expect(results).to include(redeemed)
      expect(results).not_to include(unredeemed)
    end
  end

  describe "#redeem!" do
    it "sets redeemed_at and returns true when opener is nil (anonymous user)" do
      share = create(:user_bill_share, redeemed_at: nil)
      expect(share.redeem!(opener: nil)).to be(true)
      expect(share.reload.redeemed_at).to be_present
    end

    it "sets redeemed_at and returns true when opener is a different user" do
      share = create(:user_bill_share, redeemed_at: nil)
      other_user = create(:user)
      expect(share.redeem!(opener: other_user)).to be(true)
      expect(share.reload.redeemed_at).to be_present
    end

    it "preserves the existing redeemed_at timestamp on subsequent calls and returns true" do
      share = create(:user_bill_share, redeemed_at: nil)
      original_time = 2.hours.ago.change(usec: 0)
      share.update!(redeemed_at: original_time)

      other_user = create(:user)
      expect(share.redeem!(opener: other_user)).to be(true)
      expect(share.reload.redeemed_at).to eq(original_time)
    end

    it "returns false without setting redeemed_at when opener is the creator" do
      user = create(:user)
      share = create(:user_bill_share, user:, redeemed_at: nil)
      expect(share.redeem!(opener: user)).to be(false)
      expect(share.reload.redeemed_at).to be_nil
    end
  end

  describe "cascading deletion (dependent: :destroy)" do
    it "destroys associated user_bill_shares when user is destroyed" do
      share = create(:user_bill_share)
      expect { share.user.destroy }
        .to change { described_class.where(id: share.id).count }.from(1).to(0)
    end

    it "destroys associated user_bill_shares when bill is destroyed" do
      share = create(:user_bill_share)
      expect { share.bill.destroy }
        .to change { described_class.where(id: share.id).count }.from(1).to(0)
    end
  end
end
