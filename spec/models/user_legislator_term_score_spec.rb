# == Schema Information
#
# Table name: user_legislator_term_scores
# Database name: primary
#
#  id                         :integer          not null, primary key
#  count_agreed               :integer          default(0), not null
#  count_disagreed            :integer          default(0), not null
#  count_legislator_abstained :integer          default(0), not null
#  count_no_legislator_vote   :integer          default(0), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  legislator_term_id         :integer          not null
#  user_legislator_id         :integer          not null
#
# Indexes
#
#  index_user_legislator_term_scores_on_ul_and_term  (user_legislator_id,legislator_term_id) UNIQUE
#
# Foreign Keys
#
#  legislator_term_id  (legislator_term_id => legislator_terms.id)
#  user_legislator_id  (user_legislator_id => user_legislators.id)
#
require "rails_helper"

# Counts of how often one user agreed with one legislator during one term. These are
# the rows ScoreRecomputeService writes, and the serializer adds them up to show a
# legislator's lifetime record.
RSpec.describe UserLegislatorTermScore, type: :model do
  describe "validations" do
    it "defaults all counters to 0" do
      score = build(:user_legislator_term_score)
      expect(score.count_agreed).to eq(0)
      expect(score.count_disagreed).to eq(0)
      expect(score.count_no_legislator_vote).to eq(0)
      expect(score.count_legislator_abstained).to eq(0)
    end

    it "requires a user_legislator" do
      score = build(:user_legislator_term_score, user_legislator: nil)
      expect(score).not_to be_valid
    end

    it "requires a legislator_term" do
      score = build(:user_legislator_term_score, legislator_term: nil)
      expect(score).not_to be_valid
    end

    it "rejects a duplicate (user_legislator, legislator_term) pair" do
      user_legislator = create(:user_legislator)
      legislator_term = create(:legislator_term, legislator: user_legislator.legislator)
      create(:user_legislator_term_score, user_legislator:, legislator_term:)

      dup = build(:user_legislator_term_score, user_legislator:, legislator_term:)

      expect(dup).not_to be_valid
      expect(dup.errors[:legislator_term_id]).to be_present
    end

    it "allows the same user_legislator across different legislator_terms" do
      user_legislator = create(:user_legislator)
      term_a = create(:legislator_term, legislator: user_legislator.legislator)
      term_b = create(:legislator_term, :prior_term, legislator: user_legislator.legislator)

      create(:user_legislator_term_score, user_legislator:, legislator_term: term_a)
      other = build(:user_legislator_term_score, user_legislator:, legislator_term: term_b)

      expect(other).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a user_legislator and a legislator_term" do
      score = create(:user_legislator_term_score)
      expect(score.user_legislator).to be_a(UserLegislator)
      expect(score.legislator_term).to be_a(LegislatorTerm)
    end

    it "resolves legislator and user through user_legislator" do
      user_legislator = create(:user_legislator)
      score = create(:user_legislator_term_score, user_legislator:)

      expect(score.legislator).to eq(user_legislator.legislator)
      expect(score.user).to eq(user_legislator.user)
    end
  end

  describe "UserLegislator#user_legislator_term_scores" do
    it "resolves the association" do
      user_legislator = create(:user_legislator)
      score = create(:user_legislator_term_score, user_legislator:)

      expect(user_legislator.user_legislator_term_scores).to include(score)
    end
  end
end
