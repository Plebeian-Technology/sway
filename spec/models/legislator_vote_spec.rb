# == Schema Information
#
# Table name: legislator_votes
# Database name: primary
#
#  id            :integer          not null, primary key
#  inferred      :boolean          default(FALSE), not null
#  source        :string           not null
#  support       :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  bill_id       :integer          not null
#  legislator_id :integer          not null
#
# Indexes
#
#  index_legislator_votes_on_bill_id                    (bill_id)
#  index_legislator_votes_on_bill_id_and_legislator_id  (bill_id,legislator_id) UNIQUE
#  index_legislator_votes_on_legislator_id              (legislator_id)
#
# Foreign Keys
#
#  bill_id        (bill_id => bills.id)
#  legislator_id  (legislator_id => legislators.id)
#
require "rails_helper"

RSpec.describe LegislatorVote, type: :model do
  describe "factory term binding" do
    # @lat: [[legislator-vote-fixture-tests#Term-owned legislator]]
    it "uses the supplied term's legislator when no legislator is overridden" do
      term = create(:legislator_term)

      vote = create(:legislator_vote, legislator_term: term)

      expect(vote.legislator_id).to eq(term.legislator_id)
    end

    # @lat: [[legislator-vote-fixture-tests#Default vote]]
    it "creates a manual, non-inferred FOR vote without creating a term" do
      vote = create(:legislator_vote)

      expect(LegislatorTerm.where(legislator_id: vote.legislator_id)).to be_empty
      expect(vote.source).to eq("manual")
      expect(vote.inferred).to be false
      expect(vote.support).to eq(LegislatorVote::Support::FOR)
    end

    # @lat: [[legislator-vote-fixture-tests#Traits and explicit vote overrides]]
    it "preserves support and inferred traits alongside explicit caller overrides" do
      for_vote = create(:legislator_vote, :for)
      against_vote = create(:legislator_vote, :against, :inferred, source: "congress")
      abstain_vote = create(:legislator_vote, :abstain)
      overridden_vote = create(:legislator_vote, :against, :inferred,
        support: "FOR", inferred: false, source: "open_states")

      expect(for_vote.support).to eq("FOR")
      expect(against_vote.support).to eq("AGAINST")
      expect(against_vote.inferred).to be true
      expect(against_vote.source).to eq("congress")
      expect(abstain_vote.support).to eq("ABSTAIN")
      expect(overridden_vote.support).to eq("FOR")
      expect(overridden_vote.inferred).to be false
      expect(overridden_vote.source).to eq("open_states")
    end
  end

  describe "Support constants" do
    it "defines FOR / AGAINST / ABSTAIN" do
      expect(LegislatorVote::Support::FOR).to eq("FOR")
      expect(LegislatorVote::Support::AGAINST).to eq("AGAINST")
      expect(LegislatorVote::Support::ABSTAIN).to eq("ABSTAIN")
    end

    it "lists all three in ALL constant" do
      expect(LegislatorVote::Support::ALL).to include("FOR", "AGAINST", "ABSTAIN")
    end
  end

  describe "SOURCES constant" do
    it "includes all source values" do
      expect(LegislatorVote::SOURCES).to contain_exactly("manual", "congress", "open_states", "legistar", "generic")
    end
  end

  describe "validations" do
    it "is invalid with a support value outside the allowed set" do
      vote = build(:legislator_vote, support: "MAYBE")
      expect(vote).not_to be_valid
    end

    it "is invalid without a source (presence check)" do
      vote = build(:legislator_vote, source: nil)
      expect(vote).not_to be_valid
      expect(vote.errors[:source].join).to include("can't be blank")
    end

    it "is invalid with a source value outside SOURCES (inclusion check)" do
      vote = build(:legislator_vote, source: "garbage")
      expect(vote).not_to be_valid
      expect(vote.errors[:source].join).to include("is not included in the list")
    end

    it "accepts source='manual' and saves successfully" do
      expect { create(:legislator_vote, source: "manual") }.not_to raise_error
    end

    it "accepts source='congress' and saves successfully" do
      expect { create(:legislator_vote, source: "congress") }.not_to raise_error
    end

    it "accepts source='open_states' and saves successfully" do
      expect { create(:legislator_vote, source: "open_states") }.not_to raise_error
    end

    it "accepts source='legistar' and saves successfully" do
      expect { create(:legislator_vote, source: "legistar") }.not_to raise_error
    end

    it "accepts source='generic' and saves successfully" do
      expect { create(:legislator_vote, source: "generic") }.not_to raise_error
    end
  end

  describe "associations" do
    it "belongs to a legislator" do
      expect(create(:legislator_vote).legislator).to be_a(Legislator)
    end

    it "belongs to a bill" do
      expect(create(:legislator_vote).bill).to be_a(Bill)
    end
  end

  # The transform-and-uppercase step now runs in before_validation, so the raw
  # value gets normalized once the record is validated, not right when it is
  # built.
  describe "support normalization" do
    it "transforms 'yea' to FOR" do
      vote = build(:legislator_vote, support: "yea")
      vote.valid?
      expect(vote.support).to eq(LegislatorVote::Support::FOR)
    end

    it "transforms 'nay' to AGAINST" do
      vote = build(:legislator_vote, support: "nay")
      vote.valid?
      expect(vote.support).to eq(LegislatorVote::Support::AGAINST)
    end
  end

  describe "interesting-score recompute trigger" do
    it "enqueues RecomputeBillInterestingScoreJob on save, sibling to :update_scores" do
      bill = create(:bill)
      expect {
        create(:legislator_vote, bill: bill)
      }.to have_enqueued_job(RecomputeBillInterestingScoreJob).with(bill.id).exactly(1).times
    end

    # Destroying a vote fires the recompute too. Without that, reseeding or
    # removing a legislator (Legislator has_many :legislator_votes,
    # dependent: :destroy) would leave each affected bill's latest score
    # reflecting votes that no longer exist.
    it "enqueues RecomputeBillInterestingScoreJob on destroy (WR-02)" do
      bill = create(:bill)
      vote = create(:legislator_vote, bill: bill)
      expect {
        vote.destroy!
      }.to have_enqueued_job(RecomputeBillInterestingScoreJob).with(bill.id).exactly(1).times
    end
  end

  describe "(bill_id, legislator_id) uniqueness" do
    # @lat: [[legislator-vote-fixture-tests#Duplicate bill and legislator]]
    it "rejects a second vote for the same bill + legislator" do
      vote = create(:legislator_vote)

      expect {
        LegislatorVote.create!(
          bill: vote.bill,
          legislator: vote.legislator,
          support: LegislatorVote::Support::AGAINST,
          source: "manual"
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  # :update_scores is a plain after_commit callback. It enqueues
  # OnLegislatorVoteUpdateScoresJob with the legislator_id, not the record
  # itself (passing the record would fail GlobalID deserialization after a
  # destroy), and it skips saves that changed nothing.
  describe "agreement-score recompute trigger" do
    it "M-L5: a save that does not change support enqueues nothing" do
      vote = create(:legislator_vote, source: "manual")

      expect {
        vote.update!(source: "congress")
      }.not_to have_enqueued_job(OnLegislatorVoteUpdateScoresJob)
    end

    it "enqueues the job with only the legislator_id on create" do
      legislator = create(:legislator)

      expect {
        create(:legislator_vote, legislator: legislator)
      }.to have_enqueued_job(OnLegislatorVoteUpdateScoresJob).with(legislator.id).exactly(1).times
    end

    it "enqueues the job with only the legislator_id when support changes" do
      vote = create(:legislator_vote, :for)

      expect {
        vote.update!(support: LegislatorVote::Support::AGAINST)
      }.to have_enqueued_job(OnLegislatorVoteUpdateScoresJob).with(vote.legislator_id).exactly(1).times
    end

    it "enqueues the job with only the legislator_id on destroy" do
      vote = create(:legislator_vote)

      expect {
        vote.destroy!
      }.to have_enqueued_job(OnLegislatorVoteUpdateScoresJob).with(vote.legislator_id).exactly(1).times
    end
  end

  describe "feed update broadcast trigger" do
    it "enqueues FeedUpdateBroadcastJob on create when inferred is false" do
      legislator = create(:legislator)
      active_user = create(:user)
      inactive_user = create(:user)
      create(:user_legislator, user: active_user, legislator: legislator, active: true)
      create(:user_legislator, user: inactive_user, legislator: legislator, active: false)

      expect {
        create(:legislator_vote, legislator: legislator, inferred: false)
      }.to have_enqueued_job(FeedUpdateBroadcastJob).with([active_user.id]).exactly(1).times
    end

    it "enqueues nothing on create when inferred is true" do
      legislator = create(:legislator)
      active_user = create(:user)
      create(:user_legislator, user: active_user, legislator: legislator, active: true)

      expect {
        create(:legislator_vote, legislator: legislator, inferred: true)
      }.not_to have_enqueued_job(FeedUpdateBroadcastJob)
    end

    it "enqueues FeedUpdateBroadcastJob once when confirming an inferred vote" do
      legislator = create(:legislator)
      active_user = create(:user)
      create(:user_legislator, user: active_user, legislator: legislator, active: true)
      vote = create(:legislator_vote, legislator: legislator, inferred: true)

      expect {
        vote.update!(inferred: false)
      }.to have_enqueued_job(FeedUpdateBroadcastJob).with([active_user.id]).exactly(1).times
    end

    it "enqueues nothing on other vote updates" do
      legislator = create(:legislator)
      active_user = create(:user)
      create(:user_legislator, user: active_user, legislator: legislator, active: true)
      vote = create(:legislator_vote, legislator: legislator, inferred: false, source: "manual")

      expect {
        vote.update!(source: "congress")
      }.not_to have_enqueued_job(FeedUpdateBroadcastJob)
    end
  end
end
