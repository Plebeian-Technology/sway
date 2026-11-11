# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: representative_reassignments
# Database name: primary
#
#  id                     :integer          not null, primary key
#  dismissed_at           :datetime
#  notified_at            :datetime
#  reassignment_type      :integer          default("district_changed"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  district_id            :integer
#  legislator_id          :integer
#  previous_district_id   :integer
#  previous_legislator_id :integer
#  user_id                :integer          not null
#
# Indexes
#
#  idx_rep_reassign_filled_unique                                (user_id,district_id,legislator_id) UNIQUE WHERE previous_legislator_id IS NULL
#  idx_rep_reassign_full_unique                                  (user_id,district_id,legislator_id,previous_legislator_id) UNIQUE WHERE previous_legislator_id IS NOT NULL AND legislator_id IS NOT NULL
#  idx_rep_reassign_user_active                                  (user_id,dismissed_at)
#  idx_rep_reassign_vacant_unique                                (user_id,district_id,previous_legislator_id) UNIQUE WHERE legislator_id IS NULL
#  index_representative_reassignments_on_district_id             (district_id)
#  index_representative_reassignments_on_legislator_id           (legislator_id)
#  index_representative_reassignments_on_previous_district_id    (previous_district_id)
#  index_representative_reassignments_on_previous_legislator_id  (previous_legislator_id)
#  index_representative_reassignments_on_user_id                 (user_id)
#
# Foreign Keys
#
#  district_id             (district_id => districts.id)
#  legislator_id           (legislator_id => legislators.id)
#  previous_district_id    (previous_district_id => districts.id)
#  previous_legislator_id  (previous_legislator_id => legislators.id)
#  user_id                 (user_id => users.id) ON DELETE => cascade
#
RSpec.describe RepresentativeReassignment, type: :model do
  let(:user) { create(:user) }
  let(:district) { create(:district) }
  let(:previous_district) { create(:district) }
  let(:legislator) { create(:legislator, district:) }
  let(:previous_legislator) { create(:legislator, district: previous_district) }

  describe "associations" do
    it "belongs to user, district, previous_district, legislator, previous_legislator" do
      record = described_class.create!(
        user: user,
        district: district,
        previous_district: previous_district,
        legislator: legislator,
        previous_legislator: previous_legislator,
        reassignment_type: :district_changed
      )

      expect(record.user).to eq(user)
      expect(record.district).to eq(district)
      expect(record.previous_district).to eq(previous_district)
      expect(record.legislator).to eq(legislator)
      expect(record.previous_legislator).to eq(previous_legislator)
    end
  end

  describe "enums" do
    it "defines the 4 reassignment types" do
      expect(described_class.reassignment_types).to eq(
        {
          "district_changed" => 0,
          "successor_seeded" => 1,
          "vacant_seat" => 2,
          "vacancy_filled" => 3
        }
      )
    end
  end

  describe "scopes" do
    let!(:reassignment_pending) do
      described_class.create!(
        user: user,
        district: district,
        legislator: legislator,
        reassignment_type: :vacancy_filled
      )
    end

    let!(:reassignment_dismissed) do
      described_class.create!(
        user: user,
        district: previous_district,
        previous_legislator: previous_legislator,
        reassignment_type: :vacant_seat,
        dismissed_at: 1.hour.ago,
        notified_at: 1.hour.ago
      )
    end

    describe ".pending_in_app" do
      it "returns only records where dismissed_at is nil ordered by created_at desc" do
        expect(described_class.pending_in_app).to include(reassignment_pending)
        expect(described_class.pending_in_app).not_to include(reassignment_dismissed)
      end
    end

    describe ".pending_delivery" do
      it "returns only records where notified_at is nil" do
        expect(described_class.pending_delivery).to include(reassignment_pending)
        expect(described_class.pending_delivery).not_to include(reassignment_dismissed)
      end
    end
  end

  describe "#dismiss!" do
    it "sets dismissed_at to the current time" do
      record = described_class.create!(
        user: user,
        district: district,
        legislator: legislator,
        reassignment_type: :vacancy_filled
      )

      expect { record.dismiss! }.to change(record, :dismissed_at).from(nil)
      expect(record.dismissed_at).to be_present
    end
  end

  describe "partial unique index deduplication" do
    it "enforces uniqueness for full transitions (both legislators present)" do
      described_class.create!(
        user: user,
        district: district,
        previous_legislator: previous_legislator,
        legislator: legislator,
        reassignment_type: :successor_seeded
      )

      expect {
        described_class.create!(
          user: user,
          district: district,
          previous_legislator: previous_legislator,
          legislator: legislator,
          reassignment_type: :successor_seeded
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "enforces uniqueness for vacant seat transitions (legislator is null)" do
      described_class.create!(
        user: user,
        district: district,
        previous_legislator: previous_legislator,
        legislator: nil,
        reassignment_type: :vacant_seat
      )

      expect {
        described_class.create!(
          user: user,
          district: district,
          previous_legislator: previous_legislator,
          legislator: nil,
          reassignment_type: :vacant_seat
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "enforces uniqueness for vacancy filled transitions (previous_legislator is null)" do
      described_class.create!(
        user: user,
        district: district,
        previous_legislator: nil,
        legislator: legislator,
        reassignment_type: :vacancy_filled
      )

      expect {
        described_class.create!(
          user: user,
          district: district,
          previous_legislator: nil,
          legislator: legislator,
          reassignment_type: :vacancy_filled
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
