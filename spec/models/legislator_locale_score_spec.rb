# == Schema Information
#
# Table name: legislator_locale_scores
# Database name: primary
#
#  id                         :integer          not null, primary key
#  count_agreed               :integer          default(0), not null
#  count_disagreed            :integer          default(0), not null
#  count_legislator_abstained :integer          default(0), not null
#  count_no_legislator_vote   :integer          default(0), not null
#  distinct_voter_count       :integer          default(0), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  legislator_term_id         :integer          not null
#
# Indexes
#
#  index_legislator_locale_scores_on_legislator_term_id  (legislator_term_id) UNIQUE
#
require "rails_helper"

RSpec.describe LegislatorLocaleScore, type: :model do
  describe "validations" do
    it "defaults all counters to 0" do
      lls = build(:legislator_locale_score)
      expect(lls.count_agreed).to eq(0)
      expect(lls.count_disagreed).to eq(0)
      expect(lls.count_legislator_abstained).to eq(0)
      expect(lls.count_no_legislator_vote).to eq(0)
    end
  end

  describe "associations" do
    it "belongs to a legislator_term" do
      score = create(:legislator_locale_score)
      expect(score.legislator_term).to be_a(LegislatorTerm)
    end

    it "belongs to a legislator transitionally, through the legislator_term" do
      term = create(:legislator_term)
      score = create(:legislator_locale_score, legislator_term: term)
      expect(score.legislator).to eq(term.legislator)
    end
  end

  describe "#to_builder" do
    it "surfaces all four counters and legislator_id (through legislator_term)" do
      score = create(:legislator_locale_score)
      score.update!(count_agreed: 3, count_disagreed: 5, count_legislator_abstained: 1, count_no_legislator_vote: 2)
      json = score.to_sway_json
      expect(json["legislator_id"]).to eq(score.legislator.id)
      expect(json["count_agreed"]).to eq(3)
      expect(json["count_disagreed"]).to eq(5)
      expect(json["count_legislator_abstained"]).to eq(1)
      expect(json["count_no_legislator_vote"]).to eq(2)
    end
  end
end
