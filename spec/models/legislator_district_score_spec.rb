# == Schema Information
#
# Table name: legislator_district_scores
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
#  index_legislator_district_scores_on_legislator_term_id  (legislator_term_id) UNIQUE
#
require "rails_helper"

RSpec.describe LegislatorDistrictScore, type: :model do
  describe "validations" do
    it "defaults all counters to 0" do
      lds = build(:legislator_district_score)
      expect(lds.count_agreed).to eq(0)
      expect(lds.count_disagreed).to eq(0)
      expect(lds.count_legislator_abstained).to eq(0)
      expect(lds.count_no_legislator_vote).to eq(0)
    end
  end

  describe "associations" do
    it "belongs to a legislator_term" do
      score = create(:legislator_district_score)
      expect(score.legislator_term).to be_a(LegislatorTerm)
    end

    it "belongs to a legislator transitionally, through the legislator_term" do
      term = create(:legislator_term)
      score = create(:legislator_district_score, legislator_term: term)
      expect(score.legislator).to eq(term.legislator)
    end
  end
end
