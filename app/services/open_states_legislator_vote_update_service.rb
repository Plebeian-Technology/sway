# https://v3.openstates.org/bills/{jurisdiction}/{session}/{bill_id}

# frozen_string_literal: true
# typed: true

class OpenStatesLegislatorVoteUpdateService
  extend T::Sig

  sig { returns(Bill) }
  attr_reader :bill

  sig { params(bill_id: Integer).void }
  def initialize(bill_id)
    @bill = T.let(Bill.includes(:sway_locale, :votes).find(bill_id), Bill)
  end

  sig { void }
  def run
    return unless bill.sway_locale.regional?

    senate
    house
  end

  private

  def senate
    senate_roll_call_vote_number = bill.vote&.senate_roll_call_vote_number
    return if senate_roll_call_vote_number.blank?

    T.cast(
      Scraper::OpenStates::Senate::LegislatorVotes.new(bill.sway_locale.region_code, bill.introduced_date_time_utc.year, bill.external_id).process,
      T::Array[Scraper::OpenStates::Senate::Vote]
    ).each do |vote|
      create(senator(vote), vote)
    end
  end

  def house
    house_roll_call_vote_number = bill.vote&.house_roll_call_vote_number
    return if house_roll_call_vote_number.blank?

    T.cast(
      Scraper::OpenStates::House::LegislatorVotes.new(bill.sway_locale.region_code, bill.introduced_date_time_utc.year, bill.external_id).process,
      T::Array[Scraper::OpenStates::House::Vote]
    ).each do |vote|
      create(representative(vote), vote)
    end
  end

  sig do
    params(legislator_id: T.nilable(Integer),
      vote: T.any(Scraper::OpenStates::Senate::Vote, Scraper::OpenStates::House::Vote)).void
  end
  def create(legislator_id, vote)
    LegislatorVote.find_or_create_by(bill_id: @bill.id, support: vote.support, legislator_id:) unless legislator_id.nil?
  end

  sig { params(vote: Scraper::OpenStates::House::Vote).returns(T.nilable(Integer)) }
  def representative(vote)
    Legislator.where(external_id: vote.external_id).select(:id).first&.id
  end

  sig { params(vote: Scraper::OpenStates::Senate::Vote).returns(T.nilable(Integer)) }
  def senator(vote)
    Legislator.where(external_id: vote.external_id).select(:id).first&.id
  end
end
