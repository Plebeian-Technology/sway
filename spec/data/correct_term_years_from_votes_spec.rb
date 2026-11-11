# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20260731000001_correct_term_years_from_votes")

# @lat: [[current-legislator-term#Which cycle a backfilled term belongs to]]
RSpec.describe "CorrectTermYearsFromVotes data migration", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:baltimore_locale) do
    create(:sway_locale, city: "baltimore", state: "maryland", country: "United States")
  end
  let(:district) { create(:district, sway_locale: baltimore_locale) }

  def departed_member_with(votes:, term_start_year: 2024, term_end_year: 2028,
    created_on: Time.zone.local(2024, 5, 6))
    legislator = create(:legislator, sway_locale: baltimore_locale)
    legislator.update_columns(
      last_seeded_at: Time.zone.local(2026, 4, 30),
      created_at: created_on
    )
    term = create(:legislator_term, legislator:, district:, term_start_year:, term_end_year:)

    votes.each_with_index do |date, index|
      bill = create(:bill, sway_locale: baltimore_locale,
        house_vote_date_time_utc: date,
        scheduled_release_date_utc: Time.zone.local(2030, 1, 1) + index.days)
      create(:legislator_vote, legislator:, bill:, legislator_term: term)
    end

    [legislator, term]
  end

  it "moves a departed member's term back to the cycle their votes prove" do
    _legislator, term = departed_member_with(votes: [Time.zone.local(2024, 3, 4)])

    CorrectTermYearsFromVotes.new.up

    expect(term.reload).to have_attributes(term_start_year: 2020, term_end_year: 2024)
  end

  it "stops the departed member counting as currently serving" do
    legislator, _term = departed_member_with(votes: [Time.zone.local(2024, 3, 4)])

    travel_to Time.zone.local(2026, 6, 1) do
      expect(legislator.reload.active_term).to be_present # the defect, before

      CorrectTermYearsFromVotes.new.up

      expect(legislator.reload.active_term).to be_nil
      expect(Legislator.serving).not_to include(legislator)
    end
  end

  it "leaves a sitting member whose votes are in the current cycle alone" do
    _legislator, term = departed_member_with(votes: [Time.zone.local(2025, 6, 1)])

    expect { CorrectTermYearsFromVotes.new.up }
      .not_to(change { term.reload.attributes.slice("term_start_year", "term_end_year") })
  end

  # The brief's hard requirement: this runs on machines in different states, and
  # legislator_terms is UNIQUE(legislator_id, term_start_year).
  it "changes nothing on a second run" do
    _legislator, term = departed_member_with(votes: [Time.zone.local(2024, 3, 4)])
    CorrectTermYearsFromVotes.new.up
    after_first = term.reload.attributes.slice("term_start_year", "term_end_year")

    expect { CorrectTermYearsFromVotes.new.up }.not_to(change { term.reload.attributes.slice("term_start_year", "term_end_year") })
    expect(after_first).to eq("term_start_year" => 2020, "term_end_year" => 2024)
  end

  describe "when it cannot prove the cycle it refuses to guess" do
    it "leaves a legislator with no votes exactly as it found them" do
      legislator = create(:legislator, sway_locale: baltimore_locale)
      term = create(:legislator_term, legislator:, district:, term_start_year: 2024, term_end_year: 2028)

      expect { CorrectTermYearsFromVotes.new.up }
        .not_to(change { term.reload.attributes.slice("term_start_year", "term_end_year") })
    end

    it "leaves a row alone when its votes predate the row itself" do
      congress_locale = create(:sway_locale, city: "congress", state: "congress", country: "United States")
      congress_district = create(:district, sway_locale: congress_locale)
      newcomer = create(:legislator, sway_locale: congress_locale)
      term = create(:legislator_term, legislator: newcomer, district: congress_district,
        term_start_year: 2026, term_end_year: 2028)
      bill = create(:bill, sway_locale: congress_locale,
        house_vote_date_time_utc: Time.zone.local(2024, 6, 1),
        scheduled_release_date_utc: Time.zone.local(2031, 6, 1))
      create(:legislator_vote, legislator: newcomer, bill:, legislator_term: term)
      newcomer.update_columns(created_at: Time.zone.local(2026, 7, 23))

      expect { CorrectTermYearsFromVotes.new.up }
        .not_to(change { term.reload.attributes.slice("term_start_year", "term_end_year") })
    end

    it "leaves a legislator whose votes straddle a handover alone" do
      _legislator, term = departed_member_with(
        votes: [Time.zone.local(2024, 6, 1), Time.zone.local(2025, 6, 1)]
      )

      expect { CorrectTermYearsFromVotes.new.up }
        .not_to(change { term.reload.attributes.slice("term_start_year", "term_end_year") })
    end
  end

  # Correcting in place rather than deleting and recreating is what keeps the
  # score rows attached. Every score table keys on legislator_term, so a term
  # that was destroyed would take its scores with it.
  it "keeps score rows attached to the term it corrects" do
    _legislator, term = departed_member_with(votes: [Time.zone.local(2024, 3, 4)])
    score = create(:legislator_locale_score, legislator_term: term)

    CorrectTermYearsFromVotes.new.up

    expect(score.reload.legislator_term_id).to eq(term.id)
    expect(term.reload.term_start_year).to eq(2020)
  end

  # A senator's term runs 6 years, not the 2 the locale's cycle implies.
  # Recomputing the length here would silently shorten it.
  it "slides a term without changing how many years it runs" do
    congress_locale = create(:sway_locale, city: "congress", state: "congress", country: "United States")
    congress_district = create(:district, sway_locale: congress_locale)
    senator = create(:legislator, sway_locale: congress_locale)
    term = create(:legislator_term, legislator: senator, district: congress_district,
      term_start_year: 2023, term_end_year: 2029, title: "Sen.")
    bill = create(:bill, sway_locale: congress_locale,
      house_vote_date_time_utc: Time.zone.local(2026, 3, 1),
      scheduled_release_date_utc: Time.zone.local(2031, 1, 1))
    create(:legislator_vote, legislator: senator, bill:, legislator_term: term)

    CorrectTermYearsFromVotes.new.up

    expect(term.reload).to have_attributes(term_start_year: 2025, term_end_year: 2031)
  end
end
