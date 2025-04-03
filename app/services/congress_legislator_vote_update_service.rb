# frozen_string_literal: true
# typed: true

# Creates LegislatorVotes for Congressional Legislators when a new Bill is created in the Congress sway locale.
class CongressLegislatorVoteUpdateService
  extend T::Sig

  CONGRESS = 119

  sig { params(bill_id: Integer).void }
  def initialize(bill_id)
    @bill = Bill.includes(:sway_locale, :votes).find(bill_id)
    @legislators = @bill.sway_locale.legislators
  end

  sig { void }
  def run
    return unless @bill.sway_locale.congress?

    senate
    house
  end

  private

  def senate
    return unless @bill.vote&.senate_roll_call_vote_number

    T.cast(
      Scraper::Congress::Senate::LegislatorVotes.new(CONGRESS, @bill.vote.senate_roll_call_vote_number).process,
      T::Array[Scraper::Congress::Senate::Vote]
    ).each do |vote|
      create(senator(vote), vote)
    end
  end

  def house
    return unless @bill.vote&.house_roll_call_vote_number

    T.cast(
      Scraper::Congress::House::LegislatorVotes.new(@bill.external_id, @bill.vote.house_roll_call_vote_number).process,
      T::Array[Scraper::Congress::House::Vote]
    ).each do |vote|
      create(representative(vote), vote)
    end
  end

  sig do
    params(legislator_id: T.nilable(Integer),
      vote: T.any(Scraper::Congress::Senate::Vote, Scraper::Congress::House::Vote)).void
  end
  def create(legislator_id, vote)
    LegislatorVote.find_or_create_by(bill_id: @bill.id, support: vote.support, legislator_id:) unless legislator_id.nil?
  end

  sig { params(vote: Scraper::Congress::House::Vote).returns(T.nilable(Integer)) }
  def representative(vote)
    @legislators.find { |l| l.external_id == vote.external_id }&.id
  end

  sig { params(vote: Scraper::Congress::Senate::Vote).returns(T.nilable(Integer)) }
  def senator(vote)
    legislators = @legislators.select do |l|
      l.first_name == vote.first_name.strip &&
        l.last_name == vote.last_name.strip &&
        [vote.party, Legislator.to_party_name_from_char(T.let(vote.party.strip, String))].include?(l.party) &&
        l.title == "Sen."
    end

    # binding.pry if legislators.empty?
    return nil if legislators.empty?

    if legislators.size == 1
      legislators.first&.id
    else
      ls = Legislator.where(id: legislators).includes(district: :sway_locale).filter do |legislator|
        legislator.sway_locale.region_code == vote.state_code.upcase
      end
      return nil if ls.empty? || ls.size > 1

      ls.first&.id
    end
  end
end
