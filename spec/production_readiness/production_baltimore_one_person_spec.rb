# frozen_string_literal: true

require "rails_helper"

# @lat: [[production-baltimore-one-person-verification#Why the join is by person, not by name or by seat]]
RSpec.describe "Production snapshot Baltimore council identity", :production_snapshot, type: :model do
  include_context "production snapshot (migrated)"

  let(:baltimore) { SwayLocale.resolve_by_computed_name("baltimore-maryland-united_states") }
  let(:baltimore_rows) { Legislator.where(sway_locale_id: baltimore.id).to_a }

  it "holds one row per person, whether or not they are still in office" do
    doubled =
      baltimore_rows
        .group_by { |legislator| legislator.full_name.downcase }
        .select { |_, group| group.size > 1 }
        .map { |name, group| "#{name}: #{group.map(&:external_id).join(", ")}" }

    expect(doubled).to be_empty,
      "the same person still has more than one row:\n  #{doubled.join("\n  ")}"
  end

  it "leaves twenty rows where there were thirty-two" do
    expect(baltimore_rows.size).to eq(20)
  end

  # @lat: [[production-baltimore-one-person-verification#Why the join is by person, not by name or by seat]]
  it "keeps the people who left, with their own records" do
    departed = %w[
      kristefer-burnett-2020
      eric-costello-2020
      nick-mosby-2020
      robert-stokes-2020
    ]

    departed.each do |external_id|
      row = Legislator.find_by(sway_locale_id: baltimore.id, external_id: external_id)
      expect(row).not_to be_nil, "#{external_id} was retired, and nothing said they left office"
      expect(row&.legislator_votes&.count).to be_positive
    end
  end

  it "gives the twelve who were re-elected both of their terms" do
    two_term_people =
      baltimore_rows.select { |legislator| legislator.legislator_terms.count == 2 }

    expect(two_term_people.size).to eq(12)
    two_term_people.each do |legislator|
      years = legislator.legislator_terms.map(&:term_start_year).sort
      expect(years).to eq([2020, 2024])
    end
  end

  # @lat: [[production-baltimore-one-person-verification#Why the vote-coverage check is widened past Baltimore]]
  it "puts every vote inside a term that person really held" do
    terms_by_legislator =
      LegislatorTerm
        .includes(district: :sway_locale)
        .where(legislator_id: baltimore_rows.map(&:id))
        .group_by(&:legislator_id)

    uncovered =
      LegislatorVote
        .includes(:bill)
        .where(legislator_id: baltimore_rows.map(&:id))
        .filter_map { |vote|
          bill = vote.bill
          anchor = bill.house_vote_date_time_utc || bill.senate_vote_date_time_utc ||
            bill.introduced_date_time_utc

          terms = terms_by_legislator.fetch(vote.legislator_id, [])
          next if TermWindow.covering(anchor.to_date, terms)

          "legislator #{vote.legislator_id} voted on #{bill.external_id} " \
          "(#{anchor.to_date}) outside every term they hold"
        }

    expect(uncovered).to be_empty, "\n  #{uncovered.join("\n  ")}"
  end

  # @lat: [[production-baltimore-one-person-verification#Why the vote-coverage check is widened past Baltimore]]
  it "leaves no vote in any locale for the earliest-term fallback to catch" do
    terms_by_legislator = LegislatorTerm.includes(district: :sway_locale).group_by(&:legislator_id)

    uncovered =
      LegislatorVote
        .includes(:bill, legislator: :sway_locale)
        .filter_map { |vote|
          bill = vote.bill
          anchor = bill.house_vote_date_time_utc || bill.senate_vote_date_time_utc ||
            bill.introduced_date_time_utc
          next if TermWindow.covering(anchor.to_date, terms_by_legislator.fetch(vote.legislator_id, []))

          "#{vote.legislator.sway_locale.name} legislator #{vote.legislator_id} " \
          "on #{bill.external_id} (#{anchor.to_date})"
        }

    expect(uncovered).to be_empty, "\n  #{uncovered.join("\n  ")}"
  end

  it "keeps the old name resolvable, so the mapping is not thrown away" do
    cohen = LegislatorIdentifier.legislator_for(
      sway_locale: baltimore,
      identity: LegislatorIdentity.new(
        source: LegislatorIdentity::CURATED_PERSON, value: "zeke-cohen-2020"
      )
    )

    expect(cohen).not_to be_nil
    expect(cohen&.full_name).to eq("Zeke Cohen")
    expect(cohen&.external_id).to eq("baltimore-council-president|zeke-cohen")
  end

  it "leaves no reader seeing the same person twice" do
    repeated =
      User.find_each.flat_map { |user|
        user
          .user_legislators
          .where(active: true)
          .map(&:legislator)
          .select { |legislator| legislator.sway_locale_id == baltimore.id }
          .group_by { |legislator| legislator.full_name.downcase }
          .select { |_, group| group.size > 1 }
          .map { |name, group| "user #{user.id}: #{name} listed #{group.size} times" }
      }

    expect(repeated).to be_empty, repeated.join("\n  ")
  end

  # The agreement a reader had recorded with these people for 2020-2024 is
  # history, not a duplicate. 20260803000001 deleted rows like these, correctly,
  # because they counted nothing; these count four years of votes.
  it "keeps the agreement counted under the retired rows' terms" do
    kept =
      UserLegislatorTermScore
        .joins(legislator_term: {legislator: :sway_locale})
        .where(sway_locales: {id: baltimore.id})
        .where(legislator_terms: {term_start_year: 2020})

    expect(kept.count).to be_positive
  end
end
