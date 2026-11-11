# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: bill_interesting_scores
# Database name: primary
#
#  id               :integer          not null, primary key
#  computed_at      :datetime         not null
#  normalized_score :float            not null
#  raw_score        :float            not null
#  signals          :text             not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  bill_id          :integer          not null
#
# Indexes
#
#  index_bill_interesting_scores_on_bill_id_and_id  (bill_id,id)
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#
RSpec.describe BillInterestingScore, type: :model do
  describe "associations" do
    it "belongs to a bill" do
      score = create(:bill_interesting_score)
      expect(score.bill).to be_a(Bill)
    end
  end

  describe "persistence shape" do
    it "persists raw_score, normalized_score, the full per-signal breakdown, and computed_at" do
      bill = create(:bill)
      computed_at = 5.minutes.ago
      score =
        BillInterestingScore.create!(
          bill: bill,
          raw_score: 27.5,
          normalized_score: 0.275,
          signals: {
            "vote_defection_score" => 15.0,
            "vote_abstention_score" => 0.0,
            "org_split_score" => 12.5,
            "timeliness_score" => 0.0,
            "real_for" => 4,
            "real_against" => 3,
            "real_abstain" => 1,
            "org_for" => 2,
            "org_against" => 1
          },
          computed_at: computed_at
        )

      reloaded = BillInterestingScore.find(score.id)
      expect(reloaded.raw_score).to eq(27.5)
      expect(reloaded.normalized_score).to eq(0.275)
      expect(reloaded.computed_at).to be_within(1.second).of(computed_at)
      expect(reloaded.signals).to eq(
        {
          "vote_defection_score" => 15.0,
          "vote_abstention_score" => 0.0,
          "org_split_score" => 12.5,
          "timeliness_score" => 0.0,
          "real_for" => 4,
          "real_against" => 3,
          "real_abstain" => 1,
          "org_for" => 2,
          "org_against" => 1
        }
      )
    end

    it "round-trips signals as a Hash (SQLite stores JSON as text)" do
      score = create(:bill_interesting_score)
      expect(score.reload.signals).to be_a(Hash)
    end
  end

  describe "append-only — no uniqueness constraint" do
    it "allows multiple rows for the same bill" do
      bill = create(:bill)
      create(:bill_interesting_score, bill: bill, raw_score: 10.0)
      create(:bill_interesting_score, bill: bill, raw_score: 20.0)

      expect(BillInterestingScore.where(bill: bill).count).to eq(2)
    end

    it "never updates an existing row — each recompute is a new INSERT" do
      bill = create(:bill)
      first = create(:bill_interesting_score, bill: bill, raw_score: 10.0)
      second = create(:bill_interesting_score, bill: bill, raw_score: 15.0)

      expect(first.id).not_to eq(second.id)
      expect(BillInterestingScore.find(first.id).raw_score).to eq(10.0)
    end
  end

  describe "latest-per-bill resolution" do
    it "resolves the latest row via ORDER BY id DESC" do
      bill = create(:bill)
      create(:bill_interesting_score, bill: bill, raw_score: 10.0)
      latest = create(:bill_interesting_score, bill: bill, raw_score: 30.0)

      resolved = BillInterestingScore.where(bill: bill).order(id: :desc).first!
      expect(resolved).to eq(latest)
      expect(resolved.raw_score).to eq(30.0)
    end
  end
end
