# frozen_string_literal: true

# @lat: [[legislators-controller-design#Bill of the Month voting record lives on the detail payload]]
class LegislatorBillOfTheMonthVoteResource < ApplicationResource
  attribute :bill_id do |bill|
    bill.id
  end

  attributes :external_id, :title, :status

  attribute :scheduled_release_date_utc do |bill|
    bill.scheduled_release_date_utc&.iso8601
  end

  attribute :legislator_vote do |bill|
    legislator_vote_for(bill)
  end

  attribute :user_vote do |bill|
    user_vote_for(bill)
  end

  attribute :alignment do |bill|
    alignment_for(bill)
  end

  private

  def legislator_vote_for(bill)
    params.dig(:legislator_votes_by_bill_id, bill.id)&.support
  end

  def user_vote_for(bill)
    params.dig(:user_votes_by_bill_id, bill.id)&.support
  end

  def alignment_for(bill)
    legislator_support = legislator_vote_for(bill)
    user_support = user_vote_for(bill)
    return nil unless LegislatorVote::Support::FOR_AGAINST.include?(legislator_support) &&
      LegislatorVote::Support::FOR_AGAINST.include?(user_support)

    (user_support == legislator_support) ? "agreed" : "disagreed"
  end
end
