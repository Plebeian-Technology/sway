# frozen_string_literal: true

require "rails_helper"

# @lat: [[voter-privacy-threshold#Legislator scores are sent as percentages]]
RSpec.describe UserLegislatorTermScoreResource, type: :serializer do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale:, name: "#{sway_locale.region_code}1") }
  let(:legislator) { create(:legislator, district:) }
  let(:term) { create(:legislator_term, legislator:, district:) }
  let(:prior_term) { create(:legislator_term, :prior_term, legislator:, district:) }
  let(:user_legislator) { create(:user_legislator, user: create(:user), legislator:) }

  percent_keys = %w[agreed_percent disagreed_percent no_legislator_vote_percent legislator_abstained_percent]

  def current_term_score
    term_score = create(:user_legislator_term_score, user_legislator:, legislator_term: term, count_agreed: 2)
    described_class.new(term_score).serializable_hash.deep_stringify_keys
  end

  def lifetime_score
    described_class.lifetime_hash_for(user_legislator.reload).deep_stringify_keys
  end

  %i[legislator_district_score legislator_locale_score].each do |family|
    describe family.to_s do
      it "withholds every percentage when nine distinct users stand behind the score" do
        create(family, legislator_term: term, count_agreed: 20, count_disagreed: 7, distinct_voter_count: 9)

        score = current_term_score[family.to_s]

        expect(score["comparison_suppressed"]).to be(true)
        expect(score.values_at(*percent_keys)).to all(be_nil)
        expect(score["voter_agreement_percent"]).to be_nil
        expect(score).not_to have_key("voters_needed")
        expect(score.keys).to match_array(percent_keys + %w[voter_agreement_percent legislator_id comparison_suppressed])
      end

      it "sends whole-number percentages that sum to 100 when ten distinct users stand behind the score" do
        create(family, legislator_term: term, distinct_voter_count: 10,
          count_agreed: 1, count_disagreed: 1, count_no_legislator_vote: 1, count_legislator_abstained: 0)

        score = current_term_score[family.to_s]

        expect(score["comparison_suppressed"]).to be(false)
        expect(score.values_at(*percent_keys)).to all(be_an(Integer))
        expect(score.values_at(*percent_keys).sum).to eq(100)
        expect(score["legislator_abstained_percent"]).to eq(0)
        expect(score).not_to have_key("voters_needed")
        expect(score.keys).to match_array(percent_keys + %w[voter_agreement_percent legislator_id comparison_suppressed])
      end

      it "sends the agreed share of agreed and disagreed pairs, computed from the counters" do
        create(family, legislator_term: term, distinct_voter_count: 10,
          count_agreed: 3, count_disagreed: 2, count_no_legislator_vote: 495)

        score = current_term_score[family.to_s]

        expect(score.values_at("agreed_percent", "disagreed_percent")).to eq([1, 0])
        expect(score["voter_agreement_percent"]).to eq(60)
      end

      it "sends the agreed share even when both rounded shares of all pairs are zero" do
        create(family, legislator_term: term, distinct_voter_count: 10,
          count_agreed: 2, count_disagreed: 2, count_no_legislator_vote: 996)

        expect(current_term_score[family.to_s]["voter_agreement_percent"]).to eq(50)
      end

      it "sends no agreed share when no pair was agreed or disagreed" do
        create(family, legislator_term: term, distinct_voter_count: 10, count_no_legislator_vote: 5)

        score = current_term_score[family.to_s]

        expect(score["comparison_suppressed"]).to be(false)
        expect(score["voter_agreement_percent"]).to be_nil
      end

      it "suppresses the lifetime figure when any summed term is under the minimum" do
        create(family, legislator_term: term, count_agreed: 30, distinct_voter_count: 10)
        create(family, legislator_term: prior_term, count_agreed: 4, distinct_voter_count: 4)

        score = lifetime_score[family.to_s]

        expect(score["comparison_suppressed"]).to be(true)
        expect(score.values_at(*percent_keys)).to all(be_nil)
        expect(score["voter_agreement_percent"]).to be_nil
        expect(score.keys).to match_array(percent_keys + %w[voter_agreement_percent legislator_id comparison_suppressed])
      end

      it "sends lifetime percentages when every summed term reaches the minimum" do
        create(family, legislator_term: term, count_agreed: 30, distinct_voter_count: 10)
        create(family, legislator_term: prior_term, count_disagreed: 10, distinct_voter_count: 12)

        score = lifetime_score[family.to_s]

        expect(score["comparison_suppressed"]).to be(false)
        expect(score["agreed_percent"]).to eq(75)
        expect(score["disagreed_percent"]).to eq(25)
        expect(score["voter_agreement_percent"]).to eq(75)
      end

      it "leaves a term with no counted votes out of the lifetime check" do
        create(family, legislator_term: term, count_agreed: 30, distinct_voter_count: 10)
        create(family, legislator_term: prior_term, distinct_voter_count: 0)

        score = lifetime_score[family.to_s]

        expect(score["comparison_suppressed"]).to be(false)
        expect(score["agreed_percent"]).to eq(100)
      end

      it "leaves a stale term's counters out of the published lifetime figure" do
        create(family, legislator_term: term, count_agreed: 30, distinct_voter_count: 12)
        create(family, legislator_term: prior_term, count_disagreed: 8, distinct_voter_count: 0)

        score = lifetime_score[family.to_s]

        expect(score["comparison_suppressed"]).to be(false)
        expect(score["agreed_percent"]).to eq(100)
        expect(score["disagreed_percent"]).to eq(0)
      end

      it "suppresses the lifetime figure when every term is stale" do
        create(family, legislator_term: term, count_agreed: 30, distinct_voter_count: 0)
        create(family, legislator_term: prior_term, count_disagreed: 8, distinct_voter_count: 0)

        score = lifetime_score[family.to_s]

        expect(score["comparison_suppressed"]).to be(true)
        expect(score.values_at(*percent_keys)).to all(be_nil)
      end
    end
  end

  it "keeps the user's own counters free of the group fields" do
    create(:legislator_district_score, legislator_term: term, count_agreed: 20, distinct_voter_count: 10)

    own_score = current_term_score

    expect(own_score["count_agreed"]).to eq(2)
    expect(own_score.keys & (percent_keys + %w[voter_agreement_percent comparison_suppressed])).to be_empty
    expect(lifetime_score.keys & (percent_keys + %w[voter_agreement_percent comparison_suppressed])).to be_empty
  end
end
