# typed: true

class CongressLegislatorVoteUpdateService
  extend T::Sig

  sig { params(bill_id: Integer).void }
  def initialize(bill_id)
    @bill = Bill.includes(:sway_locale, :votes).find(bill_id)
  end

  sig { void }
  def run

    nil unless @bill.sway_locale.is_congress?

    senate
    house
  end

  private

  def senate
    return unless @bill.vote&.senate_roll_call_vote_number

    T.cast(
      Scraper::Senate::LegislatorVotes.new(Census::CONGRESS, @bill.vote.senate_roll_call_vote_number).process,
      T::Array[Scraper::Senate::Vote]
    ).each do |vote|
      create(senator(vote), vote)
    end
  end

  def house
    return unless @bill.vote&.house_roll_call_vote_number

    T.cast(
      Scraper::House::LegislatorVotes.new(@bill.external_id, @bill.vote.house_roll_call_vote_number).process,
      T::Array[Scraper::House::Vote]
    ).each do |vote|
      create(representative(vote), vote)
    end
  end

  sig { params(legislator_id: T.nilable(Integer), vote: T.any(Scraper::Senate::Vote, Scraper::House::Vote)).void }
  def create(legislator_id, vote)
    LegislatorVote.find_or_create_by(bill_id: @bill.id, support: vote.support, legislator_id:) unless legislator_id.nil?
  end

  sig { params(vote: Scraper::House::Vote).returns(T.nilable(Integer)) }
  def representative(vote)
    Legislator.where(external_id: vote.external_id).select(:id).first&.id
  end

  sig { params(vote: Scraper::Senate::Vote).returns(T.nilable(Integer)) }
  def senator(vote)
    legislators = Legislator.where(
      first_name: vote.first_name,
      last_name: vote.last_name,
      party: [vote.party, Legislator.to_party_name_from_char(vote.party)],
      title: "Sen."
    ).select(:id)
    return nil if legislators.empty?

    if legislators.size == 1
      legislators.first&.id
    else
      ls = Legislator.where(id: legislators).includes(:address).filter do |legislator|
        legislator.address&.region_code == vote.state_code.upcase
      end
      return nil if ls.empty? || ls.size > 1

      ls.first&.id
    end
  end
end
