# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: roll_calls
# Database name: primary
#
#  id                           :integer          not null, primary key
#  house_roll_call_vote_number  :integer
#  senate_roll_call_vote_number :integer
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  bill_id                      :integer          not null
#
# Indexes
#
#  index_roll_calls_on_bill_id  (bill_id)
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#
RSpec.describe RollCall, type: :model do
  describe "validations" do
    it "is valid with factory defaults" do
      expect(build(:roll_call)).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a bill" do
      expect(build(:roll_call).bill).to be_a(Bill)
    end
  end

  describe "attributes" do
    it "exposes house and senate roll call vote numbers" do
      roll_call = build(:roll_call)
      expect(roll_call.house_roll_call_vote_number).to eq(142)
      expect(roll_call.senate_roll_call_vote_number).to eq(108)
    end
  end

  describe "#create_legislator_votes (WR-01)" do
    it "enqueues LegislatorVoteFetchJob for Baltimore (local?) bills" do
      baltimore_locale = create(:sway_locale, city: "baltimore",
        state: "maryland",
        country: "united_states")
      expect(baltimore_locale.local?).to be(true)
      bill = create(:bill, sway_locale: baltimore_locale, external_version: "2024-01")
      roll_call_attrs = attributes_for(:roll_call).merge(bill_id: bill.id)
      expect {
        RollCall.create!(roll_call_attrs)
      }.to have_enqueued_job(LegislatorVoteFetchJob).with(bill.id).exactly(1).times
    end

    it "enqueues LegislatorVoteFetchJob for congress? bills (no inline HTTP)" do
      congress_locale = create(:sway_locale, city: "congress",
        state: "congress",
        country: "united_states")
      expect(congress_locale.congress?).to be(true)
      bill = create(:bill, sway_locale: congress_locale)
      roll_call_attrs = attributes_for(:roll_call).merge(bill_id: bill.id)
      expect {
        RollCall.create!(roll_call_attrs)
      }.to have_enqueued_job(LegislatorVoteFetchJob).with(bill.id).exactly(1).times
    end

    it "enqueues LegislatorVoteFetchJob for regional? bills (no inline HTTP)" do
      regional_locale = create(:sway_locale, city: "maryland",
        state: "maryland",
        country: "united_states")
      expect(regional_locale.regional?).to be(true)
      bill = create(:bill, sway_locale: regional_locale)
      roll_call_attrs = attributes_for(:roll_call).merge(bill_id: bill.id)
      expect {
        RollCall.create!(roll_call_attrs)
      }.to have_enqueued_job(LegislatorVoteFetchJob).with(bill.id).exactly(1).times
    end

    it "does NOT call GenericLegislatorVoteUpdateService inline on RollCall.create" do
      congress_locale = create(:sway_locale, city: "congress",
        state: "congress",
        country: "united_states")
      bill = create(:bill, sway_locale: congress_locale)
      expect_any_instance_of(GenericLegislatorVoteUpdateService).not_to receive(:call)
      RollCall.create!(attributes_for(:roll_call).merge(bill_id: bill.id))
    end
  end
end
