# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: user_address_changes
# Database name: primary
#
#  id                          :integer          not null, primary key
#  activated_district_ids      :json             not null
#  activated_legislator_ids    :json             not null
#  deactivated_district_ids    :json             not null
#  deactivated_legislator_ids  :json             not null
#  new_sway_locale_ids         :json             not null
#  previous_sway_locale_ids    :json             not null
#  prior_vote_count            :integer          default(0), not null
#  prior_voted_bill_ids        :json             not null
#  prior_voted_sway_locale_ids :json             not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  new_address_id              :integer          not null
#  previous_address_id         :integer          not null
#  user_id                     :integer          not null
#
# Indexes
#
#  index_user_address_changes_on_created_at              (created_at)
#  index_user_address_changes_on_new_address_id          (new_address_id)
#  index_user_address_changes_on_previous_address_id     (previous_address_id)
#  index_user_address_changes_on_user_id                 (user_id)
#  index_user_address_changes_on_user_id_and_created_at  (user_id,created_at)
#
# Foreign Keys
#
#  user_id  (user_id => users.id) ON DELETE => cascade
#
RSpec.describe UserAddressChange, type: :model do
  describe "associations" do
    it "belongs to user, previous_address, and new_address, and exposes user.user_address_changes" do
      user = create(:user)
      previous_address = create(:address, street: "100 E Pratt St")
      new_address = create(:address, street: "200 E Pratt St")
      record = described_class.create!(
        user: user,
        previous_address: previous_address,
        new_address: new_address
      )

      expect(record.user).to eq(user)
      expect(record.previous_address).to eq(previous_address)
      expect(record.new_address).to eq(new_address)
      expect(user.user_address_changes).to contain_exactly(record)
    end
  end

  describe "validations" do
    it "requires previous_address_id and new_address_id" do
      user = create(:user)
      record = described_class.new(user: user)

      expect(record).not_to be_valid
      expect(record.errors[:previous_address_id]).to be_present
      expect(record.errors[:new_address_id]).to be_present
    end

    it "rejects previous_address_id equal to new_address_id" do
      user = create(:user)
      previous_address = create(:address, street: "100 E Pratt St")
      record = described_class.new(
        user: user,
        previous_address: previous_address,
        new_address: previous_address
      )

      expect(record).not_to be_valid
      expect(record.errors[:new_address_id]).to include("must be different from previous address")
    end

    it "rejects negative prior_vote_count" do
      user = create(:user)
      previous_address = create(:address, street: "100 E Pratt St")
      new_address = create(:address, street: "200 E Pratt St")
      record = described_class.new(
        user: user,
        previous_address: previous_address,
        new_address: new_address,
        prior_vote_count: -1
      )

      expect(record).not_to be_valid
      expect(record.errors[:prior_vote_count]).to be_present
    end
  end

  describe "JSON ID array normalization" do
    it "normalizes all ID list columns to sorted unique integer arrays" do
      user = create(:user)
      previous_address = create(:address, street: "100 E Pratt St")
      new_address = create(:address, street: "200 E Pratt St")
      record = described_class.create!(
        user: user,
        previous_address: previous_address,
        new_address: new_address,
        deactivated_legislator_ids: ["12", 5, 12, "invalid", nil],
        activated_legislator_ids: [9, "3", 9],
        deactivated_district_ids: [4, 2, 4],
        activated_district_ids: ["8", 1],
        previous_sway_locale_ids: [2, 1, 2],
        new_sway_locale_ids: ["3", 1],
        prior_voted_bill_ids: [30, 10, 20, 10],
        prior_voted_sway_locale_ids: [5, 2, 5]
      )

      expect(record.deactivated_legislator_ids).to eq([5, 12])
      expect(record.activated_legislator_ids).to eq([3, 9])
      expect(record.deactivated_district_ids).to eq([2, 4])
      expect(record.activated_district_ids).to eq([1, 8])
      expect(record.previous_sway_locale_ids).to eq([1, 2])
      expect(record.new_sway_locale_ids).to eq([1, 3])
      expect(record.prior_voted_bill_ids).to eq([10, 20, 30])
      expect(record.prior_voted_sway_locale_ids).to eq([2, 5])
    end
  end

  describe "predicates" do
    it "computes cross_district? when deactivated and activated district sets differ" do
      user = create(:user)
      previous_address = create(:address, street: "100 E Pratt St")
      new_address = create(:address, street: "200 E Pratt St")
      same_district = build(
        :user_address_change,
        user: user,
        previous_address: previous_address,
        new_address: new_address,
        deactivated_district_ids: [1, 2],
        activated_district_ids: [2, 1]
      )
      empty_districts = build(
        :user_address_change,
        user: user,
        previous_address: previous_address,
        new_address: new_address,
        deactivated_district_ids: [],
        activated_district_ids: []
      )
      different_district = build(
        :user_address_change,
        user: user,
        previous_address: previous_address,
        new_address: new_address,
        deactivated_district_ids: [1],
        activated_district_ids: [2]
      )

      expect(same_district.cross_district?).to be(false)
      expect(empty_districts.cross_district?).to be(false)
      expect(different_district.cross_district?).to be(true)
    end

    it "computes cross_sway_locale? when previous and new sway locale sets differ" do
      user = create(:user)
      previous_address = create(:address, street: "100 E Pratt St")
      new_address = create(:address, street: "200 E Pratt St")
      same_locale = build(
        :user_address_change,
        user: user,
        previous_address: previous_address,
        new_address: new_address,
        previous_sway_locale_ids: [1, 2],
        new_sway_locale_ids: [2, 1]
      )
      empty_locales = build(
        :user_address_change,
        user: user,
        previous_address: previous_address,
        new_address: new_address,
        previous_sway_locale_ids: [],
        new_sway_locale_ids: []
      )
      different_locale = build(
        :user_address_change,
        user: user,
        previous_address: previous_address,
        new_address: new_address,
        previous_sway_locale_ids: [1],
        new_sway_locale_ids: [2]
      )

      expect(same_locale.cross_sway_locale?).to be(false)
      expect(empty_locales.cross_sway_locale?).to be(false)
      expect(different_locale.cross_sway_locale?).to be(true)
    end

    it "computes voted_before_switch? from prior_vote_count" do
      no_votes = build(:user_address_change, prior_vote_count: 0)
      with_votes = build(:user_address_change, prior_vote_count: 3)

      expect(no_votes.voted_before_switch?).to be(false)
      expect(with_votes.voted_before_switch?).to be(true)
    end
  end

  describe "UserLegislator.active scope" do
    it "returns only active user_legislator rows" do
      user = create(:user)
      active_ul = create(:user_legislator, user: user, active: true)
      inactive_ul = create(:user_legislator, user: user, active: false)

      expect(UserLegislator.active).to include(active_ul)
      expect(UserLegislator.active).not_to include(inactive_ul)
      expect(user.user_legislators.active).to contain_exactly(active_ul)
    end
  end

  describe "deletion resilience" do
    it "allows destroying a previous address or the user without foreign key errors" do
      user = create(:user)
      previous_address = create(:address, street: "100 E Pratt St")
      new_address = create(:address, street: "200 E Pratt St")
      create(:user_address, user: user, address: new_address)
      change = described_class.create!(
        user: user,
        previous_address: previous_address,
        new_address: new_address
      )

      expect { previous_address.destroy! }.not_to raise_error
      expect(change.reload.previous_address).to be_nil
      expect { user.destroy! }.to change(described_class, :count).by(-1)
    end
  end
end
