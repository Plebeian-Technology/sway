# frozen_string_literal: true

require "rails_helper"

# @lat: [[current-legislator-term#Roster evidence for observed departures]]
RSpec.describe RetireDepartedLegislatorsService do
  let(:maryland) { create(:sway_locale, :maryland) }
  let(:congress) { create(:sway_locale, :congress) }
  let(:today) { Date.new(2026, 8, 12) }

  # A person with a term that is running today, keyed the way the seeder keys
  # them: external_id holds the identity value the roster would build.
  def seated(sway_locale, external_id, start_year: 2023, end_year: 2027)
    district = District.find_or_create_by!(name: "MD1", sway_locale: sway_locale)
    legislator = create(:legislator, sway_locale: sway_locale, external_id: external_id, district: district)
    create(
      :legislator_term,
      legislator: legislator,
      district: district,
      term_start_year: start_year,
      term_end_year: end_year
    )
    legislator
  end

  describe "a locale whose roster lists only sitting members" do
    it "does not end the term of somebody the roster no longer names and logs missing official date evidence" do
      departed = seated(maryland, "ocd-person/gone")
      stayed = seated(maryland, "ocd-person/here")
      expect(departed.reload.serving?).to be(true)

      expect(Sentry).not_to receive(:capture_message)
      expect(SwayLogging).to receive(:warn).with(
        "retire_departed_members.observed_departure",
        hash_including(
          sway_locale: maryland.name,
          external_id: departed.external_id,
          observed_on: today.to_s,
          note: a_string_including("missing official departure date evidence")
        )
      )

      result = described_class.new(maryland, ["ocd-person/here"], observed_on: today).call

      expect(result).to eq([])
      term = departed.legislator_terms.first #: LegislatorTerm
      expect(term.ended_on).to be_nil
      expect(term.ended_on_source).to be_nil
      expect(departed.reload.serving?).to be(true)
      expect(stayed.reload.serving?).to be(true)
    end

    it "causes no term-date write in an incomplete download with missing members" do
      departed = seated(maryland, "ocd-person/missing")
      stayed = seated(maryland, "ocd-person/present")

      expect(Sentry).not_to receive(:capture_message)
      expect(SwayLogging).to receive(:warn).with(
        "retire_departed_members.observed_departure",
        hash_including(
          sway_locale: maryland.name,
          external_id: departed.external_id,
          observed_on: today.to_s,
          note: a_string_including("missing official departure date evidence")
        )
      )

      result = described_class.new(maryland, ["ocd-person/present"], observed_on: today).call

      expect(result).to eq([])
      expect(departed.legislator_terms.first&.ended_on).to be_nil
      expect(departed.reload.serving?).to be(true)
      expect(stayed.reload.serving?).to be(true)
    end

    it "causes no term-date write on repeated roster downloads" do
      departed = seated(maryland, "ocd-person/gone")
      described_class.new(maryland, [], observed_on: today).call
      described_class.new(maryland, [], observed_on: today + 30).call

      expect(departed.legislator_terms.first&.ended_on).to be_nil
      expect(departed.reload.serving?).to be(true)
    end

    it "never writes over a date the jurisdiction published" do
      departed = seated(maryland, "ocd-person/gone")
      term = departed.legislator_terms.first #: LegislatorTerm
      term.update!(
        ended_on: Date.new(2026, 3, 1),
        ended_on_source: LegislatorTerm::DateSource::PUBLISHED
      )

      described_class.new(maryland, [], observed_on: today).call

      expect(term.reload.ended_on).to eq(Date.new(2026, 3, 1))
      expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
    end

    it "preserves legacy inferred dates byte-for-byte" do
      departed = seated(maryland, "ocd-person/gone")
      term = departed.legislator_terms.first #: LegislatorTerm
      term.update!(
        ended_on: Date.new(2026, 2, 15),
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )

      described_class.new(maryland, [], observed_on: today).call

      expect(term.reload.ended_on).to eq(Date.new(2026, 2, 15))
      expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::OBSERVED)
    end
  end

  # @lat: [[current-legislator-term#Roster identity during seeding]]
  describe "a seat the roster named but could not fill" do
    it "leaves the person sitting in it in office" do
      cohen = seated(maryland, "baltimore-council-president|zeke-cohen")

      described_class.new(
        maryland, [], unidentified_entries: ["baltimore-council-president"], observed_on: today
      ).call

      expect(cohen.legislator_terms.first&.ended_on).to be_nil
      expect(cohen.reload.serving?).to be(true)
    end

    # A seat may only say "still in office", never "these two are one person".
    # So it accounts for whoever sits in THAT seat and nobody else, but absence does not write dates.
    it "does not write dates even for somebody sitting in an unmentioned seat" do
      cohen = seated(maryland, "baltimore-council-president|zeke-cohen")
      parker = seated(maryland, "baltimore-district-1|mark-parker")

      described_class.new(
        maryland, [], unidentified_entries: ["baltimore-council-president"], observed_on: today
      ).call

      expect(cohen.reload.serving?).to be(true)
      expect(parker.legislator_terms.first&.ended_on).to be_nil
      expect(parker.reload.serving?).to be(true)
    end
  end

  # @lat: [[current-legislator-term#Departure safeguards]]
  describe "an entry naming neither a person nor a seat anybody holds" do
    it "refuses the whole run when an entry has no id or seat and reports entries_not_understood" do
      departed = seated(maryland, "ocd-person/gone")

      expect(SwayLogging).to receive(:warn).with(
        "retire_departed_members.entries_not_understood",
        hash_including(
          sway_locale: maryland.name,
          unresolved: [""],
          note: a_string_including("nobody retired — the roster carried entries naming no person and no seat")
        )
      )
      expect(Sentry).to receive(:capture_message).with(
        a_string_including("retire_departed_members.entries_not_understood in #{maryland.name}"),
        level: :warning
      )
      expect(SwayLogging).not_to receive(:warn).with("retire_departed_members.observed_departure", any_args)

      result = described_class.new(
        maryland, ["ocd-person/here"], unidentified_entries: [""], observed_on: today
      ).call

      expect(result).to eq([])
      expect(departed.legislator_terms.first&.ended_on).to be_nil
      expect(departed.reload.serving?).to be(true)
    end

    it "refuses the whole run when the seat named belongs to no serving member" do
      departed = seated(maryland, "baltimore-district-1|mark-parker")

      expect(SwayLogging).to receive(:warn).with(
        "retire_departed_members.entries_not_understood",
        hash_including(
          sway_locale: maryland.name,
          unresolved: ["baltimore-district-9"]
        )
      )
      expect(Sentry).to receive(:capture_message).with(
        a_string_including("retire_departed_members.entries_not_understood in #{maryland.name}"),
        level: :warning
      )
      expect(SwayLogging).not_to receive(:warn).with("retire_departed_members.observed_departure", any_args)

      result = described_class.new(
        maryland, [], unidentified_entries: ["baltimore-district-9"], observed_on: today
      ).call

      expect(result).to eq([])
      expect(departed.reload.serving?).to be(true)
    end
  end

  # @lat: [[current-legislator-term#Departure safeguards]]
  describe "how many people one run may retire" do
    it "refuses the whole run when too many leave and nobody arrives" do
      gone = Array.new(4) { |n| seated(maryland, "ocd-person/gone-#{n}") }
      stayed = seated(maryland, "ocd-person/here")

      expect(SwayLogging).to receive(:warn).with(
        "retire_departed_members.too_many_unreplaced",
        hash_including(
          sway_locale: maryland.name,
          departed: 4,
          arrived: 0,
          limit: 3,
          note: a_string_including("nobody retired — a roster losing this many people with no replacements")
        )
      )
      expect(Sentry).to receive(:capture_message).with(
        a_string_including("retire_departed_members.too_many_unreplaced in #{maryland.name}"),
        level: :warning
      )
      expect(SwayLogging).not_to receive(:warn).with("retire_departed_members.observed_departure", any_args)

      result = described_class.new(maryland, ["ocd-person/here"], observed_on: today).call

      expect(result).to eq([])
      expect(gone.map { |legislator| legislator.reload.serving? }).to all(be(true))
      expect(stayed.reload.serving?).to be(true)
    end

    # An election is not a truncated fetch: fifteen of Baltimore's sixteen
    # seats can change hands at once. So the bound counts UNREPLACED
    # departures.
    it "does not retire anybody even when the same number of people arrive" do
      gone = Array.new(4) { |n| seated(maryland, "ocd-person/gone-#{n}") }
      arriving = Array.new(4) { |n| "ocd-person/new-#{n}" }

      gone.each do |legislator|
        expect(SwayLogging).to receive(:warn).with(
          "retire_departed_members.observed_departure",
          hash_including(
            sway_locale: maryland.name,
            external_id: legislator.external_id,
            observed_on: today.to_s,
            note: a_string_including("missing official departure date evidence")
          )
        )
      end

      result = described_class.new(maryland, arriving, observed_on: today).call

      expect(result).to eq([])
      expect(gone.map { |legislator| legislator.reload.serving? }).to all(be(true))
      expect(gone.map { |legislator| legislator.legislator_terms.first&.ended_on }).to all(be_nil)
    end

    it "does not retire anybody when a small number of departures have no replacement" do
      gone = Array.new(3) { |n| seated(maryland, "ocd-person/gone-#{n}") }

      gone.each do |legislator|
        expect(SwayLogging).to receive(:warn).with(
          "retire_departed_members.observed_departure",
          hash_including(
            sway_locale: maryland.name,
            external_id: legislator.external_id,
            observed_on: today.to_s,
            note: a_string_including("missing official departure date evidence")
          )
        )
      end

      result = described_class.new(maryland, [], observed_on: today).call

      expect(result).to eq([])
      expect(gone.map { |legislator| legislator.reload.serving? }).to all(be(true))
      expect(gone.map { |legislator| legislator.legislator_terms.first&.ended_on }).to all(be_nil)
    end

    # A flat three is a fifth of Baltimore's sixteen seats and 1.5% of
    # Maryland's 195, so the bound is a share of the body with a floor under it.
    # Here 100 serving allows five, and four is under that.
    it "does not retire anybody in a larger body" do
      Array.new(96) { |n| seated(maryland, "ocd-person/other-#{n}") }
      gone = Array.new(4) { |n| seated(maryland, "ocd-person/gone-#{n}") }
      staying = (0...96).map { |n| "ocd-person/other-#{n}" }

      gone.each do |legislator|
        expect(SwayLogging).to receive(:warn).with(
          "retire_departed_members.observed_departure",
          hash_including(
            sway_locale: maryland.name,
            external_id: legislator.external_id,
            observed_on: today.to_s,
            note: a_string_including("missing official departure date evidence")
          )
        )
      end

      result = described_class.new(maryland, staying, observed_on: today).call

      expect(result).to eq([])
      expect(gone.map { |legislator| legislator.reload.serving? }).to all(be(true))
      expect(gone.map { |legislator| legislator.legislator_terms.first&.ended_on }).to all(be_nil)
    end
  end

  # congress.gov keeps people who have left and flags them, so absence from the
  # file proves nothing at all. Reading it as a departure would end the term of
  # everybody a partial fetch happened to miss.
  describe "a locale whose roster keeps people who have left" do
    it "does nothing, whoever is missing" do
      still_listed_upstream = seated(congress, "M000001", start_year: 2025, end_year: 2027)

      described_class.new(congress, [], observed_on: today).call

      expect(still_listed_upstream.legislator_terms.first&.ended_on).to be_nil
      expect(still_listed_upstream.reload.serving?).to be(true)
    end
  end

  it "leaves alone somebody who is already out of office" do
    already_gone = seated(maryland, "ocd-person/old", start_year: 2015, end_year: 2019)
    expect(already_gone.reload.serving?).to be(false)

    described_class.new(maryland, [], observed_on: today).call

    expect(already_gone.legislator_terms.first&.ended_on).to be_nil
  end

  describe "absence from roster causing no score recomputation or representative reassignment (R1)" do
    it "does not trigger score recomputation or alter user representation when a legislator drops out of a roster" do
      district = District.find_or_create_by!(name: "MD1", sway_locale: maryland)
      legislator = create(:legislator, sway_locale: maryland, external_id: "ocd-person/dropped", district: district)
      term = create(:legislator_term, legislator: legislator, district: district, term_start_year: 2023, term_end_year: 2027)
      user = create(:user)
      ul = create(:user_legislator, user: user, legislator: legislator, active: true)
      ud = create(:user_district, user: user, district: district, active: true)

      expect(ScoreRecomputeService).not_to receive(:recompute_legislator!)
      expect(ScoreRecomputeService).not_to receive(:recompute_user_legislator!)
      expect(ScoreUpdaterService).not_to receive(:broadcast_score_refresh)
      expect(RepresentativeReassignmentObserver).not_to receive(:observe_diff!)

      described_class.new(maryland, [], observed_on: today).call

      expect(term.reload.ended_on).to be_nil
      expect(legislator.reload.serving?).to be(true)
      expect(ul.reload.active).to be(true)
      expect(ud.reload.active).to be(true)
    end

    it "leaves legislator serving so downstream reconciliation does not deactivate representation or broadcast updates" do
      district = District.find_or_create_by!(name: "MD1", sway_locale: maryland)
      legislator = create(:legislator, sway_locale: maryland, external_id: "ocd-person/dropped", district: district)
      term = create(:legislator_term, legislator: legislator, district: district, term_start_year: 2023, term_end_year: 2027)
      user = create(:user)
      address = create(:address, region_code: "MD")
      create(:user_address, user: user, address: address)
      ul = create(:user_legislator, user: user, legislator: legislator, active: true)
      ud = create(:user_district, user: user, district: district, active: true)

      # Absence from download does not retire or mutate term date
      described_class.new(maryland, [], observed_on: today).call
      expect(term.reload.ended_on).to be_nil
      expect(legislator.reload.serving?).to be(true)

      # Downstream reconciliation resolution checks serving?
      reg_service = instance_double(SwayRegistrationService)
      allow(SwayRegistrationService).to receive(:new).and_return(reg_service)
      allow(reg_service).to receive(:district_legislators).and_return(legislator.serving? ? [legislator] : [])

      expect(RepresentativeReassignmentObserver).not_to receive(:observe_diff!)
      expect(ScoreUpdaterService).not_to receive(:broadcast_score_refresh)

      ReconcileUserDistrictsService.new(user, maryland).call

      expect(ul.reload.active).to be(true)
      expect(ud.reload.active).to be(true)
    end
  end
end
