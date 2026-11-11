# frozen_string_literal: true

require "rails_helper"

# BillInterestingScoreCalculator is looked up lazily with Object.const_get,
# so a missing class fails each example on its own rather than taking
# down the whole file.
RSpec.describe "BillInterestingScoreCalculator", type: :service do
  let(:calculator_class) { Object.const_get("BillInterestingScoreCalculator") }

  let(:congress_locale) do
    create(:sway_locale, city: "congress", state: "congress", country: "united_states")
  end
  let(:baltimore_locale) do
    create(:sway_locale, city: "baltimore", state: "MD", country: "United States")
  end

  let(:congress_district) { create(:district, sway_locale: congress_locale) }
  let(:baltimore_district) { create(:district, sway_locale: baltimore_locale) }

  # Every test bill is dated 60 days back (outside the timely window) and
  # given a staggered scheduled_release_date_utc, avoiding that column's
  # unique index.
  def build_bill(sway_locale)
    create(
      :bill,
      sway_locale: sway_locale,
      introduced_date_time_utc: 60.days.ago,
      scheduled_release_date_utc: (Bill.count + 1).days.ago
    )
  end

  def cast_vote(bill, district:, party:, support:, inferred: false)
    legislator = create(:legislator, district: district, party: party)
    create(:legislator_vote, bill: bill, legislator: legislator, support: support, inferred: inferred)
  end

  def create_org_positions(bill, for_count:, against_count:)
    for_count.times do
      create(
        :organization_bill_position,
        bill: bill,
        organization: create(:organization),
        support: "FOR",
        active: true
      )
    end
    against_count.times do
      create(
        :organization_bill_position,
        bill: bill,
        organization: create(:organization),
        support: "AGAINST",
        active: true
      )
    end
  end

  def attach_cleaned_testimony(bill, letter_count:, repeat_letters: 0, campaign_origin_letters: 0, group_count: 0)
    create(
      :bill_llm_provisioning,
      bill: bill,
      cleaned_testimony: {
        "counts" => {
          "letter_count" => letter_count,
          "repeat_letters" => repeat_letters,
          "campaign_origin_letters" => campaign_origin_letters,
          "group_count" => group_count
        }
      }
    )
  end

  describe "cross-bloc vote-defection scoring (SPEC Req 1/3)" do
    it "scores a bill with cross-party/intra-bloc defection higher than a unanimous bill" do
      unanimous_bill = build_bill(congress_locale)
      3.times do
        cast_vote(unanimous_bill, district: congress_district, party: "D", support: LegislatorVote::Support::FOR)
      end

      mixed_bill = build_bill(congress_locale)
      cast_vote(mixed_bill, district: congress_district, party: "D", support: LegislatorVote::Support::FOR)
      cast_vote(mixed_bill, district: congress_district, party: "D", support: LegislatorVote::Support::AGAINST)
      cast_vote(mixed_bill, district: congress_district, party: "R", support: LegislatorVote::Support::FOR)
      cast_vote(mixed_bill, district: congress_district, party: "R", support: LegislatorVote::Support::AGAINST)

      unanimous_result = calculator_class.new(unanimous_bill).call
      mixed_result = calculator_class.new(mixed_bill).call

      expect(mixed_result.signals["vote_defection_score"]).to be > unanimous_result.signals["vote_defection_score"]
      expect(mixed_result.raw_score).to be > unanimous_result.raw_score
    end
  end

  describe "party-line vote scores near-zero defection" do
    it "scores ~0 defection when every bloc is internally unanimous, even in an evenly-split chamber" do
      bill = build_bill(congress_locale)
      3.times { cast_vote(bill, district: congress_district, party: "D", support: LegislatorVote::Support::FOR) }
      3.times { cast_vote(bill, district: congress_district, party: "R", support: LegislatorVote::Support::AGAINST) }

      result = calculator_class.new(bill).call

      expect(result.signals["vote_defection_score"]).to eq(0.0)
    end
  end

  describe "Independent bloc defection rules (D-06a)" do
    it "contributes 0 when only a single Independent votes (a bloc of 1 cannot split)" do
      bill = build_bill(congress_locale)
      cast_vote(bill, district: congress_district, party: "I", support: LegislatorVote::Support::FOR)
      3.times { cast_vote(bill, district: congress_district, party: "D", support: LegislatorVote::Support::FOR) }

      result = calculator_class.new(bill).call

      expect(result.signals["vote_defection_score"]).to eq(0.0)
    end

    it "contributes a magnitude-scaled score when >=2 Independents split" do
      bill = build_bill(congress_locale)
      cast_vote(bill, district: congress_district, party: "I", support: LegislatorVote::Support::FOR)
      cast_vote(bill, district: congress_district, party: "I", support: LegislatorVote::Support::AGAINST)
      3.times { cast_vote(bill, district: congress_district, party: "D", support: LegislatorVote::Support::FOR) }

      result = calculator_class.new(bill).call

      expect(result.signals["vote_defection_score"]).to be > 0.0
    end
  end

  describe "abstention-rate scoring (D-06b)" do
    it "ignores a low abstention rate as noise" do
      bill = build_bill(congress_locale)
      9.times { cast_vote(bill, district: congress_district, party: "D", support: LegislatorVote::Support::FOR) }
      cast_vote(bill, district: congress_district, party: "D", support: LegislatorVote::Support::ABSTAIN)

      result = calculator_class.new(bill).call

      expect(result.signals["vote_abstention_score"]).to eq(0.0)
    end

    it "scores a high abstention rate" do
      bill = build_bill(congress_locale)
      4.times { cast_vote(bill, district: congress_district, party: "D", support: LegislatorVote::Support::FOR) }
      4.times { cast_vote(bill, district: congress_district, party: "D", support: LegislatorVote::Support::ABSTAIN) }

      result = calculator_class.new(bill).call

      expect(result.signals["vote_abstention_score"]).to be > 0.0
    end
  end

  describe "Baltimore never gets a vote-defection or close-margin term" do
    it "scores 0 defection/abstention regardless of any legislator_votes rows on a local bill" do
      bill = build_bill(baltimore_locale)
      # Even an invented split across parties must never show up as defection
      # on a Baltimore bill: a `local?` locale leaves vote signals out
      # entirely, since Baltimore publishes no real roll calls.
      cast_vote(bill, district: baltimore_district, party: "D", support: LegislatorVote::Support::FOR)
      cast_vote(bill, district: baltimore_district, party: "D", support: LegislatorVote::Support::AGAINST)

      result = calculator_class.new(bill).call

      expect(result.signals["vote_defection_score"]).to eq(0.0)
      expect(result.signals["vote_abstention_score"]).to eq(0.0)
    end
  end

  describe "org-position disagreement scoring, every locale incl. Baltimore" do
    [
      [1, 1, 10.0],
      [2, 2, 20.0],
      [5, 4, 35.6],
      [9, 1, 8.0]
    ].each do |for_count, against_count, expected|
      it "scores #{for_count}-for/#{against_count}-against as ~#{expected} on a Baltimore bill" do
        bill = build_bill(baltimore_locale)
        create_org_positions(bill, for_count: for_count, against_count: against_count)

        result = calculator_class.new(bill).call

        expect(result.signals["org_split_score"]).to be_within(0.1).of(expected)
      end
    end
  end

  # An organization position's stored value is whatever the browser sends
  # ("support"/"oppose"), so the calculator normalizes each row rather than
  # matching an exact "FOR"/"AGAINST".
  describe "wire-vocabulary support values count toward the org split (review IN-03)" do
    it "counts active 'support'/'oppose' rows as FOR/AGAINST" do
      bill = build_bill(baltimore_locale)
      create(
        :organization_bill_position,
        bill: bill,
        organization: create(:organization),
        support: "support",
        active: true
      )
      create(
        :organization_bill_position,
        bill: bill,
        organization: create(:organization),
        support: "oppose",
        active: true
      )

      result = calculator_class.new(bill).call

      expect(result.signals["org_for"]).to eq(1)
      expect(result.signals["org_against"]).to eq(1)
      # An even split, one for and one against, scores 10.0.
      expect(result.signals["org_split_score"]).to be_within(0.1).of(10.0)
    end

    it "ignores unrecognized support values instead of miscounting them" do
      bill = build_bill(baltimore_locale)
      create(
        :organization_bill_position,
        bill: bill,
        organization: create(:organization),
        support: "garbage-value",
        active: true
      )

      result = calculator_class.new(bill).call

      expect(result.signals["org_for"]).to eq(0)
      expect(result.signals["org_against"]).to eq(0)
      expect(result.signals["org_split_score"]).to eq(0.0)
    end
  end

  describe "sponsor-inferred rows excluded from vote math" do
    it "excludes inferred: true legislator_votes from defection scoring" do
      bill = build_bill(congress_locale)
      cast_vote(bill, district: congress_district, party: "D", support: LegislatorVote::Support::FOR, inferred: true)
      cast_vote(bill, district: congress_district, party: "D", support: LegislatorVote::Support::AGAINST, inferred: true)
      cast_vote(bill, district: congress_district, party: "R", support: LegislatorVote::Support::FOR, inferred: true)
      cast_vote(bill, district: congress_district, party: "R", support: LegislatorVote::Support::AGAINST, inferred: true)

      result = calculator_class.new(bill).call

      expect(result.signals["vote_defection_score"]).to eq(0.0)
      expect(result.signals["real_for"]).to eq(0)
      expect(result.signals["real_against"]).to eq(0)
    end
  end

  describe "floor behavior for a bill with no signals (Question 6)" do
    it "produces a zero-score row without erroring when nothing is present" do
      bill = build_bill(congress_locale)

      result = nil #: untyped
      expect { result = calculator_class.new(bill).call }.not_to raise_error

      expect(result.raw_score).to eq(0.0)
      expect(result.normalized_score).to eq(0.0)
      expect(result).to be_persisted
    end
  end

  describe "Baltimore testimony engagement scoring" do
    it "scores 0.0 testimony engagement when a Baltimore bill has no testimony" do
      bill = build_bill(baltimore_locale)

      result = calculator_class.new(bill).call

      expect(result.signals["testimony_engagement_score"]).to eq(0.0)
      expect(result.signals["testimony_letter_count"]).to eq(0)
      expect(result.signals["testimony_individual_count"]).to eq(0)
      expect(result.signals["testimony_campaign_count"]).to eq(0)
      expect(result.signals["testimony_repeat_count"]).to eq(0)
      expect(result.raw_score).to eq(0.0)
      expect(result.normalized_score).to eq(0.0)
    end

    it "scores Baltimore bill with rich testimony with proper weighting" do
      bill = build_bill(baltimore_locale)
      attach_cleaned_testimony(
        bill,
        letter_count: 50,
        repeat_letters: 10,
        campaign_origin_letters: 20,
        group_count: 2
      )

      result = calculator_class.new(bill).call

      expect(result.signals["testimony_engagement_score"]).to eq(28.0)
      expect(result.signals["testimony_letter_count"]).to eq(50)
      expect(result.signals["testimony_individual_count"]).to eq(20)
      expect(result.signals["testimony_campaign_count"]).to eq(2)
      expect(result.signals["testimony_repeat_count"]).to eq(10)
      expect(result.raw_score).to eq(28.0)
      expect(result.normalized_score).to eq(0.28)
    end

    it "saturates at WEIGHT_TESTIMONY_ENGAGEMENT (50.0) when testimony volume meets or exceeds cap" do
      bill = build_bill(baltimore_locale)
      attach_cleaned_testimony(
        bill,
        letter_count: 80,
        repeat_letters: 0,
        campaign_origin_letters: 0,
        group_count: 0
      )

      result = calculator_class.new(bill).call

      expect(result.signals["testimony_engagement_score"]).to eq(50.0)
      expect(result.signals["testimony_letter_count"]).to eq(80)
      expect(result.signals["testimony_individual_count"]).to eq(80)
      expect(result.raw_score).to eq(50.0)
      expect(result.normalized_score).to eq(0.5)
    end

    it "discounts repeat form campaign letters compared to organic individual letters" do
      organic_bill = build_bill(baltimore_locale)
      attach_cleaned_testimony(
        organic_bill,
        letter_count: 20,
        repeat_letters: 0,
        campaign_origin_letters: 0,
        group_count: 0
      )

      campaign_bill = build_bill(baltimore_locale)
      attach_cleaned_testimony(
        campaign_bill,
        letter_count: 20,
        repeat_letters: 0,
        campaign_origin_letters: 20,
        group_count: 1
      )

      organic_result = calculator_class.new(organic_bill).call
      campaign_result = calculator_class.new(campaign_bill).call

      expect(organic_result.signals["testimony_engagement_score"]).to eq(20.0)
      expect(campaign_result.signals["testimony_engagement_score"]).to eq(6.0)
      expect(organic_result.signals["testimony_engagement_score"]).to be > campaign_result.signals["testimony_engagement_score"]
    end

    it "normalizes against LOCAL_THEORETICAL_MAX (100.0) for Baltimore" do
      expect(calculator_class.theoretical_max(false)).to eq(100.0)
      expect(calculator_class.theoretical_max(true)).to eq(100.0)

      bill = build_bill(baltimore_locale)
      attach_cleaned_testimony(
        bill,
        letter_count: 50,
        repeat_letters: 0,
        campaign_origin_letters: 0,
        group_count: 0
      )
      create_org_positions(bill, for_count: 2, against_count: 2)

      result = calculator_class.new(bill).call

      expect(result.raw_score).to eq(70.0)
      expect(result.normalized_score).to eq(0.7)
    end

    it "falls back to Campaign records when cleaned_testimony is nil" do
      bill = build_bill(baltimore_locale)
      create(
        :campaign,
        bill: bill,
        letter_count: 30,
        sender_count: 20,
        active: true
      )

      result = calculator_class.new(bill).call

      expect(result.signals["testimony_letter_count"]).to eq(30)
      expect(result.signals["testimony_repeat_count"]).to eq(10)
      expect(result.signals["testimony_campaign_count"]).to eq(1)
      expect(result.signals["testimony_engagement_score"]).to be > 0.0
    end

    it "leaves testimony_engagement_score at 0.0 for Congress and Maryland bills" do
      bill = build_bill(congress_locale)
      attach_cleaned_testimony(
        bill,
        letter_count: 100,
        repeat_letters: 0,
        campaign_origin_letters: 0,
        group_count: 0
      )

      result = calculator_class.new(bill).call

      expect(result.signals["testimony_engagement_score"]).to eq(0.0)
      expect(result.signals["testimony_letter_count"]).to eq(0)
    end
  end
end
