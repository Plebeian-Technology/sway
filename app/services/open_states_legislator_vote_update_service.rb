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

  def scraper
    if bill.chamber == "senate"
      if bill.sway_locale.region_code == "MD"
        Scraper::Maryland::LegislatorVotes
      else
        Scraper::OpenStates::Senate::LegislatorVotes
      end
    elsif bill.sway_locale.region_code == "MD"
      Scraper::Maryland::LegislatorVotes
    else
      Scraper::OpenStates::House::LegislatorVotes
    end
  end

  def senate
    senate_roll_call_vote_number = bill.vote&.senate_roll_call_vote_number
    return if senate_roll_call_vote_number.blank?

    T
      .cast(
        scraper.new(bill, senate_roll_call_vote_number, "senate").process,
        T::Array[Scraper::OpenStates::Senate::Vote],
      )
      .each { |vote| create(senator(vote), vote) }
  end

  def house
    house_roll_call_vote_number = bill.vote&.house_roll_call_vote_number
    return if house_roll_call_vote_number.blank?

    T
      .cast(
        scraper.new(bill, house_roll_call_vote_number, "house").process,
        T::Array[Scraper::OpenStates::House::Vote],
      )
      .each { |vote| create(representative(vote), vote) }
  end

  sig do
    params(
      legislator_id: T.nilable(Integer),
      vote:
        T.any(
          Scraper::OpenStates::Senate::Vote,
          Scraper::OpenStates::House::Vote,
        ),
    ).void
  end
  def create(legislator_id, vote)
    unless legislator_id.nil?
      LegislatorVote.find_or_create_by(
        bill_id: @bill.id,
        support: vote.support,
        legislator_id:,
      )
    end
  end

  sig do
    params(vote: Scraper::OpenStates::House::Vote).returns(T.nilable(Integer))
  end
  def representative(vote)
    Legislator.where(external_id: vote.external_id).select(:id).first&.id
  end

  sig do
    params(vote: Scraper::OpenStates::Senate::Vote).returns(T.nilable(Integer))
  end
  def senator(vote)
    Legislator.where(external_id: vote.external_id).select(:id).first&.id
  end
end
