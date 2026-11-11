# frozen_string_literal: true

require "rails_helper"

RSpec.describe LegislatorBillOfTheMonthVoteResource do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale:) }
  let(:legislator) { create(:legislator, sway_locale:, district:) }
  let(:user) { create(:user) }
  let(:bill) do
    create(
      :bill,
      sway_locale:,
      legislator:,
      external_id: "HB-101",
      title: "Clean Water Act",
      scheduled_release_date_utc: Date.new(2026, 3, 15),
      status: Bill::Status::PASSED
    )
  end

  it "serializes bill attributes and nil votes when no votes exist" do
    raw = described_class.new(
      bill,
      params: {
        legislator_votes_by_bill_id: {},
        user_votes_by_bill_id: {}
      }
    ).serializable_hash #: Hash[Symbol, untyped]
    hash = raw.transform_keys(&:to_s)

    expect(hash).to eq(
      "bill_id" => bill.id,
      "external_id" => "HB-101",
      "title" => "Clean Water Act",
      "scheduled_release_date_utc" => "2026-03-15",
      "status" => Bill::Status::PASSED,
      "legislator_vote" => nil,
      "user_vote" => nil,
      "alignment" => nil
    )
  end

  it "computes agreed alignment when user and legislator both vote FOR or both vote AGAINST" do
    term = create(:legislator_term, legislator:, district:)
    for_leg_vote = create(:legislator_vote, :for, bill:, legislator:, legislator_term: term)
    for_user_vote = create(:user_vote, bill:, user:, support: LegislatorVote::Support::FOR)

    raw_for = described_class.new(
      bill,
      params: {
        legislator_votes_by_bill_id: {bill.id => for_leg_vote},
        user_votes_by_bill_id: {bill.id => for_user_vote}
      }
    ).serializable_hash #: Hash[Symbol, untyped]
    hash_for = raw_for.transform_keys(&:to_s)

    expect(hash_for["legislator_vote"]).to eq("FOR")
    expect(hash_for["user_vote"]).to eq("FOR")
    expect(hash_for["alignment"]).to eq("agreed")

    for_leg_vote.update!(support: LegislatorVote::Support::AGAINST)
    for_user_vote.update!(support: LegislatorVote::Support::AGAINST)

    raw_against = described_class.new(
      bill,
      params: {
        legislator_votes_by_bill_id: {bill.id => for_leg_vote},
        user_votes_by_bill_id: {bill.id => for_user_vote}
      }
    ).serializable_hash #: Hash[Symbol, untyped]
    hash_against = raw_against.transform_keys(&:to_s)

    expect(hash_against["legislator_vote"]).to eq("AGAINST")
    expect(hash_against["user_vote"]).to eq("AGAINST")
    expect(hash_against["alignment"]).to eq("agreed")
  end

  it "computes disagreed alignment when user and legislator vote on opposite sides" do
    term = create(:legislator_term, legislator:, district:)
    leg_vote = create(:legislator_vote, :against, bill:, legislator:, legislator_term: term)
    user_vote = create(:user_vote, bill:, user:, support: LegislatorVote::Support::FOR)

    raw = described_class.new(
      bill,
      params: {
        legislator_votes_by_bill_id: {bill.id => leg_vote},
        user_votes_by_bill_id: {bill.id => user_vote}
      }
    ).serializable_hash #: Hash[Symbol, untyped]
    hash = raw.transform_keys(&:to_s)

    expect(hash["legislator_vote"]).to eq("AGAINST")
    expect(hash["user_vote"]).to eq("FOR")
    expect(hash["alignment"]).to eq("disagreed")
  end

  it "returns nil alignment when legislator abstains or either vote is missing" do
    term = create(:legislator_term, legislator:, district:)
    abstain_leg_vote = create(:legislator_vote, :abstain, bill:, legislator:, legislator_term: term)
    user_vote = create(:user_vote, bill:, user:, support: LegislatorVote::Support::FOR)

    raw_abstain = described_class.new(
      bill,
      params: {
        legislator_votes_by_bill_id: {bill.id => abstain_leg_vote},
        user_votes_by_bill_id: {bill.id => user_vote}
      }
    ).serializable_hash #: Hash[Symbol, untyped]
    abstain_hash = raw_abstain.transform_keys(&:to_s)

    expect(abstain_hash["legislator_vote"]).to eq("ABSTAIN")
    expect(abstain_hash["user_vote"]).to eq("FOR")
    expect(abstain_hash["alignment"]).to be_nil

    raw_no_user = described_class.new(
      bill,
      params: {
        legislator_votes_by_bill_id: {bill.id => abstain_leg_vote},
        user_votes_by_bill_id: {}
      }
    ).serializable_hash #: Hash[Symbol, untyped]
    no_user_hash = raw_no_user.transform_keys(&:to_s)

    expect(no_user_hash["legislator_vote"]).to eq("ABSTAIN")
    expect(no_user_hash["user_vote"]).to be_nil
    expect(no_user_hash["alignment"]).to be_nil

    raw_no_leg = described_class.new(
      bill,
      params: {
        legislator_votes_by_bill_id: {},
        user_votes_by_bill_id: {bill.id => user_vote}
      }
    ).serializable_hash #: Hash[Symbol, untyped]
    no_leg_hash = raw_no_leg.transform_keys(&:to_s)

    expect(no_leg_hash["legislator_vote"]).to be_nil
    expect(no_leg_hash["user_vote"]).to eq("FOR")
    expect(no_leg_hash["alignment"]).to be_nil
  end
end
