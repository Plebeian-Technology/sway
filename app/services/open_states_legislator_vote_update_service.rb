# frozen_string_literal: true

# https://v3.openstates.org/bills/{jurisdiction}/{session}/{bill_id}
class OpenStatesLegislatorVoteUpdateService
  attr_reader :bill

  def initialize(bill_id)
    @bill = Bill.includes(:sway_locale, :votes).find(bill_id)
  end

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

    scraper
      .new(bill, senate_roll_call_vote_number, "senate")
      .process
      .each { |vote| create(senator(vote), vote) }
  end

  def house
    house_roll_call_vote_number = bill.vote&.house_roll_call_vote_number
    return if house_roll_call_vote_number.blank?

    scraper
      .new(bill, house_roll_call_vote_number, "house")
      .process
      .each { |vote| create(representative(vote), vote) }
  end

  def create(legislator_id, vote)
    return if legislator_id.nil?
    LegislatorVote.find_or_create_by(
      bill_id: @bill.id,
      support: vote.support,
      legislator_id:,
    )
  end

  def representative(vote)
    Legislator.where(external_id: vote.external_id).select(:id).first&.id
  end

  def senator(vote)
    Legislator.where(external_id: vote.external_id).select(:id).first&.id
  end
end
