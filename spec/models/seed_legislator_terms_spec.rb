# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "legislator")
require Rails.root.join("db", "seeds", "models", "seed_legislator_terms")

# @lat: [[seed-legislator-terms-add-correct-retire#What production_departed_members_spec.rb verifies]]
RSpec.describe SeedLegislatorTerms do
  include ActiveSupport::Testing::TimeHelpers

  let(:congress) { create(:sway_locale, city: "congress", state: "congress", country: "United States") }

  # An entry shaped like the one congress roster writes. The
  # "termsSource" key is the mark that says these terms are a COMPLETE history,
  # and it is what unlocks correcting and retiring.
  def roster_entry(terms:, current_member: true, from_history: true)
    entry = {
      "bioguideId" => "Q6VD001",
      "firstName" => "Departed",
      "lastName" => "Member",
      "partyName" => "Democrat",
      "state" => "Florida",
      "district" => 20,
      "currentMember" => current_member,
      "terms" => {"item" => terms}
    }
    entry["termsSource"] = LegislatorsCache::CongressTermHistory::SOURCE_NAME if from_history
    entry
  end

  def house_term(start_year, end_year)
    {
      "chamber" => "House of Representatives",
      "startYear" => start_year,
      "endYear" => end_year,
      "stateCode" => "FL",
      "district" => 20
    }
  end

  def seed_entry!(entry, locale_had_legislators: false)
    SeedLegislator.new(entry, congress, force: true, locale_had_legislators: locale_had_legislators).seed
    Legislator.find_by!(external_id: "Q6VD001", sway_locale: congress)
  end

  def configure_seat_chambers!(locale, mapping)
    current = locale.term_rules
    configured = SwayLocale::TermRules.new(
      convening: current.convening,
      cycle_anchor_year: current.cycle_anchor_year,
      cycle_years: current.cycle_years,
      roster_lists_only_current_legislators: current.roster_lists_only_current_legislators,
      publishes_term_history: current.publishes_term_history,
      publishes_exact_term_dates: current.publishes_exact_term_dates,
      identified_by: current.identified_by,
      seat_chambers: mapping
    )
    allow(locale).to receive(:term_rules).and_return(configured)
  end

  def curated_seat_entry(title:, office_key:, district:, first_name: "Taylor", last_name: "Seat")
    {
      "title" => title,
      "externalId" => office_key,
      "external_id" => office_key,
      "active" => true,
      "party" => "D",
      "district" => district,
      "regionCode" => "MD",
      "country" => "United States",
      "first_name" => first_name,
      "last_name" => last_name
    }
  end

  def curated_legislator_and_prepared(locale, entry, identity: nil)
    prepared = SeedPreparers::Legislators::Sway.new(entry, locale)
    prepared.define_singleton_method(:identity) { identity } if identity
    district = prepared.district || raise("Curated test entry has no district")
    legislator = create(
      :legislator,
      district: district,
      sway_locale: locale,
      external_id: "curated-#{SecureRandom.hex(8)}",
      first_name: prepared.first_name,
      last_name: prepared.last_name
    )
    [legislator, prepared, district]
  end

  def record_prepared_identity!(legislator, prepared)
    identity = prepared.identity || raise("Curated test entry has no identity")
    LegislatorIdentifier.record!(legislator: legislator, identity: identity)
  end

  def official_service_result(records:, sway_locale:)
    source_url = "https://legislature.gov/service"
    profile = {
      capability: "supported",
      publisher: "legislature.gov",
      jurisdiction: "maryland",
      source_url: source_url,
      identity_source: LegislatorIdentity::OPENSTATES,
      office_identity: records.first.fetch(:office_identity),
      records_path: "records",
      fact_type: "official_service",
      date_semantics: {start: "inclusive", end: "exclusive"},
      fields: {
        id: "id",
        office_identity: "office_identity",
        title: "title",
        start_date: "start_date",
        end_date: "end_date",
        presence: "presence",
        chamber: "chamber",
        district: "district"
      }
    }
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/service") { [200, {"Content-Type" => "application/json"}, {records: records}.to_json] }
    end
    connection = Faraday.new("https://legislature.gov") do |faraday|
      faraday.adapter :test, stubs
    end

    Legislation::Adapters::GenericRosterAdapter.new(
      {roster_rules: {official_service: profile}},
      connection: connection
    ).fetch_official_service(sway_locale: sway_locale)
  end

  def supported_service_prepared(records:, district:, sway_locale:)
    result = official_service_result(records:, sway_locale:)
    raise "official service fixture did not produce facts: #{result.coverage_gaps.inspect}" if result.facts.empty?

    fact = result.facts.fetch(0)
    OfficialEvidence::PreparedServiceEntry.new(
      official_fact: fact,
      official_service_result: result,
      district: district
    )
  end

  def service_record(identity_value: "ocd-person/12345", office_identity: "md-house-43a",
    district: "District 43A", title: "Delegate", start_date: "2023-01-11", end_date: "2027-01-13",
    chamber: "House", presence: "present")
    {
      id: identity_value,
      office_identity: office_identity,
      district: district,
      title: title,
      chamber: chamber,
      start_date: start_date,
      end_date: end_date,
      presence: presence
    }
  end

  describe "adding terms" do
    it "writes a row for every term the history proves" do
      legislator = seed_entry!(roster_entry(terms: [house_term(2021, 2023), house_term(2023, 2025)]))

      expect(legislator.legislator_terms.pluck(:term_start_year, :term_end_year))
        .to contain_exactly([2021, 2023], [2023, 2025])
    end

    # A member sworn in this week has no published history yet. They still need
    # one term row or they cannot be scored at all.
    it "writes a current term for a new member the source still lists" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(roster_entry(terms: [], from_history: false))

        expect(legislator.legislator_terms.pluck(:term_start_year, :term_end_year))
          .to eq([[2025, 2027]])
      end
    end

    # The heart of the bug. The fallback above reads the running election cycle
    # off the clock, so applying it to somebody who has LEFT hands them a fresh
    # term running to next year — which is exactly what makes them read as in
    # office.
    it "writes no current term for somebody the source no longer lists" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(roster_entry(terms: [], current_member: false, from_history: false))

        expect(legislator.legislator_terms).to be_empty
      end
    end
  end

  describe "correcting a stored term" do
    it "writes the proven end year and title over the stored ones" do
      legislator = seed_entry!(roster_entry(terms: [house_term(2025, 2027)]))
      term = legislator.legislator_terms.find_by!(term_start_year: 2025)
      term.update_columns(title: "Sen.")

      seed_entry!(roster_entry(terms: [house_term(2025, 2026)], current_member: false))

      expect(term.reload.term_end_year).to eq(2026)
      expect(term.title).to eq("Rep.")
    end

    # congress.gov reports one entry per Congress, so a senator's six-year term
    # arrives as three two-year pieces. Correcting against that list would cut
    # every senate term back to two years and put sitting senators out of
    # office.
    it "leaves the stored term alone when the list did not come from the history source" do
      legislator = seed_entry!(roster_entry(terms: [house_term(2025, 2031)]))
      term = legislator.legislator_terms.find_by!(term_start_year: 2025)

      seed_entry!(roster_entry(terms: [house_term(2025, 2027)], from_history: false))

      expect(term.reload.term_end_year).to eq(2031)
    end

    it "leaves the seat alone, even when the proven term names another one" do
      legislator = seed_entry!(roster_entry(terms: [house_term(2025, 2027)]))
      term = legislator.legislator_terms.find_by!(term_start_year: 2025)

      moved = house_term(2025, 2026).merge("district" => 6)
      seed_entry!(roster_entry(terms: [moved], current_member: false))

      expect(term.reload.district.name).to eq("FL20")
    end
  end

  # @lat: [[seed-legislator-terms-add-correct-retire#What production_departed_members_spec.rb verifies#The blast radius check]]
  describe "a member who is still serving" do
    it "has an invented term retired and a real one corrected, the same as anybody else" do
      legislator = seed_entry!(roster_entry(terms: [house_term(2021, 2023), house_term(2023, 2029)]))
      legislator.legislator_terms.create!(
        term_start_year: 2025,
        term_end_year: 2031,
        district: District.find_by!(name: "FL20", sway_locale: congress)
      )

      seed_entry!(roster_entry(terms: [house_term(2021, 2023), house_term(2023, 2027)]))

      expect(legislator.legislator_terms.reload.pluck(:term_start_year)).to contain_exactly(2021, 2023)
      expect(legislator.legislator_terms.find_by!(term_start_year: 2023).term_end_year).to eq(2027)
    end

    # Returning to the roster does not establish service dates; an existing
    # stored departure date is preserved byte-for-byte on reappearance.
    it "does not clear an existing stored departure date on reappearance" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(roster_entry(terms: [house_term(2021, 2023), house_term(2025, 2027)]))
        early = legislator.legislator_terms.find_by!(term_start_year: 2021)
        latest = legislator.legislator_terms.find_by!(term_start_year: 2025)
        early.update_columns(ended_on: Date.new(2022, 5, 1), ended_on_source: LegislatorTerm::DateSource::OBSERVED)
        latest.update_columns(ended_on: Date.new(2026, 2, 1), ended_on_source: LegislatorTerm::DateSource::OBSERVED)

        allow(Rails.logger).to receive(:info).and_call_original

        seed_entry!(roster_entry(terms: [house_term(2021, 2023), house_term(2025, 2027)]))

        expect(Rails.logger).to have_received(:info).with(
          a_string_including("#{legislator.external_id} is in the roster again — preserving existing departure date 2026-02-01")
        ).at_least(:once)

        expect(early.reload.ended_on).to eq(Date.new(2022, 5, 1))
        expect(latest.reload.ended_on).to eq(Date.new(2026, 2, 1))
        expect(latest.ended_on_source).to eq(LegislatorTerm::DateSource::OBSERVED)
        expect(legislator.reload.serving?).to be(false)
      end
    end

    it "does not clear an existing stored departure date on reappearance in a roster without history" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(roster_entry(terms: [], from_history: false))
        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        term.update_columns(ended_on: Date.new(2026, 3, 1), ended_on_source: LegislatorTerm::DateSource::OBSERVED)

        allow(Rails.logger).to receive(:info).and_call_original

        seed_entry!(roster_entry(terms: [], from_history: false))

        expect(Rails.logger).to have_received(:info).with(
          a_string_including("#{legislator.external_id} is in the roster again — preserving existing departure date 2026-03-01")
        ).at_least(:once)

        expect(term.reload.ended_on).to eq(Date.new(2026, 3, 1))
        expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::OBSERVED)
        expect(legislator.reload.serving?).to be(false)
      end
    end

    it "preserves an officially evidenced departure date byte-for-byte on reappearance in a roster without history" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(roster_entry(terms: [], from_history: false))
        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        term.update_columns(ended_on: Date.new(2026, 1, 15), ended_on_source: LegislatorTerm::DateSource::PUBLISHED)

        allow(Rails.logger).to receive(:info).and_call_original

        seed_entry!(roster_entry(terms: [], from_history: false))

        expect(Rails.logger).to have_received(:info).with(
          a_string_including("#{legislator.external_id} is in the roster again — preserving existing departure date 2026-01-15")
        ).at_least(:once)

        expect(term.reload.ended_on).to eq(Date.new(2026, 1, 15))
        expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
        expect(legislator.reload.serving?).to be(false)
      end
    end

    it "preserves an officially evidenced departure date byte-for-byte on reappearance with service history across repeated imports" do
      travel_to(Time.utc(2026, 8, 6)) do
        entry = roster_entry(terms: [house_term(2025, 2027)])
        legislator = seed_entry!(entry)
        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        term.update_columns(ended_on: Date.new(2026, 1, 15), ended_on_source: LegislatorTerm::DateSource::PUBLISHED)
        expect(legislator.reload.serving?).to be(false)

        allow(Rails.logger).to receive(:info).and_call_original

        seed_entry!(entry)

        expect(Rails.logger).to have_received(:info).with(
          a_string_including("#{legislator.external_id} is in the roster again — preserving existing departure date 2026-01-15")
        ).at_least(:once)

        expect(term.reload.ended_on).to eq(Date.new(2026, 1, 15))
        expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
        expect(legislator.reload.serving?).to be(false)

        # Repeated import
        seed_entry!(entry)

        term.reload
        expect(term.ended_on).to eq(Date.new(2026, 1, 15))
        expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
        expect(legislator.reload.serving?).to be(false)
      end
    end

    it "preserves an observed departure date byte-for-byte on reappearance with service history across repeated imports" do
      travel_to(Time.utc(2026, 8, 6)) do
        entry = roster_entry(terms: [house_term(2025, 2027)])
        legislator = seed_entry!(entry)
        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        term.update_columns(ended_on: Date.new(2026, 3, 1), ended_on_source: LegislatorTerm::DateSource::OBSERVED)
        expect(legislator.reload.serving?).to be(false)

        allow(Rails.logger).to receive(:info).and_call_original

        seed_entry!(entry)

        expect(Rails.logger).to have_received(:info).with(
          a_string_including("#{legislator.external_id} is in the roster again — preserving existing departure date 2026-03-01")
        ).at_least(:once)

        expect(term.reload.ended_on).to eq(Date.new(2026, 3, 1))
        expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::OBSERVED)
        expect(legislator.reload.serving?).to be(false)

        # Repeated import
        seed_entry!(entry)

        term.reload
        expect(term.ended_on).to eq(Date.new(2026, 3, 1))
        expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::OBSERVED)
        expect(legislator.reload.serving?).to be(false)
      end
    end

    it "preserves past term departure date and source when legislator re-enters office in a future non-consecutive term" do
      travel_to(Time.utc(2027, 2, 1)) do
        past_entry = roster_entry(terms: [house_term(2021, 2023), house_term(2023, 2025)], current_member: false)
        legislator = seed_entry!(past_entry)
        past_term = legislator.legislator_terms.find_by!(term_start_year: 2023)
        past_term.update_columns(ended_on: Date.new(2024, 6, 1), ended_on_source: LegislatorTerm::DateSource::PUBLISHED)
        expect(legislator.reload.serving?).to be(false)

        # Member is re-elected for 2027-2029 stint
        new_entry = roster_entry(
          terms: [house_term(2021, 2023), house_term(2023, 2025), house_term(2027, 2029)],
          current_member: true
        )
        seed_entry!(new_entry)

        past_term.reload
        new_term = legislator.legislator_terms.find_by!(term_start_year: 2027)

        expect(past_term.ended_on).to eq(Date.new(2024, 6, 1))
        expect(past_term.ended_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
        expect(new_term.ended_on).to be_nil
        expect(legislator.reload.serving?).to be(true)
      end
    end
  end

  # @lat: [[seed-legislator-terms-add-correct-retire#Why a published end date replaces an observed one]]
  describe "the day a term really ended" do
    # current_member: false because a real departure arrives as a departed
    # entry — the roster stopped listing the person. That is now the only
    # shape an end date is written from.
    it "records a published end date and stops the person reading as in office" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(
          roster_entry(terms: [house_term(2025, 2027).merge("endedOn" => "2026-07-11")], current_member: false)
        )

        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        expect(term.ended_on).to eq(Date.new(2026, 7, 11))
        expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
        expect(legislator.reload.serving?).to be(false)
      end
    end

    it "leaves a term with no published date running to the locale's handover day" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(roster_entry(terms: [house_term(2025, 2027)]))

        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        expect(term.ended_on).to be_nil
        expect(legislator.reload.serving?).to be(true)
      end
    end

    # The date arrives on a LATER run, once the person has dropped out of the
    # roster and the departed entry carries it.
    it "adds the date to a term stored before the history carried one" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(roster_entry(terms: [house_term(2025, 2027)]))
        expect(legislator.legislator_terms.find_by!(term_start_year: 2025).ended_on).to be_nil

        seed_entry!(
          roster_entry(terms: [house_term(2025, 2027).merge("endedOn" => "2026-07-11")], current_member: false)
        )

        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        expect(term.ended_on).to eq(Date.new(2026, 7, 11))
        expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
      end
    end

    it "promotes an observed departure date to published when published history confirms the same day" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(roster_entry(terms: [house_term(2025, 2027)]))
        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        term.update_columns(ended_on: Date.new(2026, 7, 11), ended_on_source: LegislatorTerm::DateSource::OBSERVED)

        seed_entry!(
          roster_entry(terms: [house_term(2025, 2027).merge("endedOn" => "2026-07-11")], current_member: false)
        )

        term.reload
        expect(term.ended_on).to eq(Date.new(2026, 7, 11))
        expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
      end
    end
  end

  # @lat: [[current-legislator-term#A term carries the day it really began]]
  describe "the day a term really began" do
    it "records a published start date over the observed stamp" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(
          roster_entry(terms: [house_term(2025, 2027).merge("beganOn" => "2026-07-15")]),
          locale_had_legislators: true
        )

        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        expect(term.began_on).to eq(Date.new(2026, 7, 15))
        expect(term.began_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
      end
    end

    it "promotes an observed start date to published when published history confirms the same day" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(
          roster_entry(terms: [house_term(2025, 2027)]),
          locale_had_legislators: true
        )
        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        expect(term.began_on_source).to eq(LegislatorTerm::DateSource::OBSERVED)
        expect(term.began_on).to eq(Date.new(2026, 8, 6))

        seed_entry!(
          roster_entry(terms: [house_term(2025, 2027).merge("beganOn" => "2026-08-06")])
        )

        term.reload
        expect(term.began_on).to eq(Date.new(2026, 8, 6))
        expect(term.began_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
      end
    end

    it "adds the start to a term stored before the history carried one" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(roster_entry(terms: [house_term(2025, 2027)]))
        expect(legislator.legislator_terms.find_by!(term_start_year: 2025).began_on).to be_nil

        seed_entry!(roster_entry(terms: [house_term(2025, 2027).merge("beganOn" => "2026-07-15")]))

        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        expect(term.began_on).to eq(Date.new(2026, 7, 15))
        expect(term.began_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
      end
    end
  end

  # An end date still ahead is a schedule, not a departure: two appointed
  # senators carry the day of their November 2026 special election, and
  # writing it would read both out of office that day while they still serve.
  describe "a published end date that has not arrived yet" do
    it "is not written when the term is first stored" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(
          roster_entry(terms: [house_term(2025, 2027).merge("endedOn" => "2026-11-03")])
        )

        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        expect(term.ended_on).to be_nil
        expect(legislator.reload.serving?).to be(true)
      end
    end

    it "is not written onto a term already stored" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(roster_entry(terms: [house_term(2025, 2027)]))

        seed_entry!(roster_entry(terms: [house_term(2025, 2027).merge("endedOn" => "2026-11-03")]))

        expect(legislator.legislator_terms.find_by!(term_start_year: 2025).ended_on).to be_nil
      end
    end

    it "is refused even on a departed entry — a future departure is malformed" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(
          roster_entry(terms: [house_term(2025, 2027).merge("endedOn" => "2030-01-03")], current_member: false)
        )

        expect(legislator.legislator_terms.find_by!(term_start_year: 2025).ended_on).to be_nil
      end
    end
  end

  # @lat: [[current-legislator-term#A scheduled end whose day has passed is not yet a departure]]
  describe "a scheduled end whose day has passed" do
    it "is still not a departure while the roster lists the member" do
      travel_to(Time.utc(2026, 11, 10)) do
        legislator = seed_entry!(
          roster_entry(terms: [house_term(2025, 2027).merge("endedOn" => "2026-11-03")])
        )

        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        expect(term.ended_on).to be_nil
        expect(legislator.reload.serving?).to be(true)
      end
    end

    it "is preserved on a term it was already written onto across repeated imports" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(roster_entry(terms: [house_term(2025, 2027)]))
        legislator.legislator_terms.find_by!(term_start_year: 2025).update_columns(
          ended_on: Date.new(2026, 11, 3),
          ended_on_source: LegislatorTerm::DateSource::PUBLISHED
        )
      end

      travel_to(Time.utc(2026, 11, 10)) do
        entry = roster_entry(terms: [house_term(2025, 2027).merge("endedOn" => "2026-11-03")])
        legislator = seed_entry!(entry)

        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        expect(term.ended_on).to eq(Date.new(2026, 11, 3))
        expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
        expect(legislator.reload.serving?).to be(false)

        # Repeated import
        seed_entry!(entry)

        term.reload
        expect(term.ended_on).to eq(Date.new(2026, 11, 3))
        expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
        expect(legislator.reload.serving?).to be(false)
      end
    end

    it "still writes the real past end on an earlier term of a sitting member" do
      travel_to(Time.utc(2026, 11, 10)) do
        legislator = seed_entry!(
          roster_entry(terms: [
            house_term(2023, 2025).merge("endedOn" => "2025-01-03"),
            house_term(2025, 2027).merge("endedOn" => "2026-11-03")
          ])
        )

        expect(legislator.legislator_terms.find_by!(term_start_year: 2023).ended_on)
          .to eq(Date.new(2025, 1, 3))
        expect(legislator.legislator_terms.find_by!(term_start_year: 2025).ended_on).to be_nil
      end
    end

    it "writes the end once the person drops out of the roster" do
      travel_to(Time.utc(2026, 11, 10)) do
        legislator = seed_entry!(
          roster_entry(terms: [house_term(2025, 2027).merge("endedOn" => "2026-11-03")], current_member: false)
        )

        term = legislator.legislator_terms.find_by!(term_start_year: 2025)
        expect(term.ended_on).to eq(Date.new(2026, 11, 3))
        expect(term.ended_on_source).to eq(LegislatorTerm::DateSource::PUBLISHED)
        expect(legislator.reload.serving?).to be(false)
      end
    end
  end

  describe "retiring a term no history knows about" do
    it "deletes the row and the score rows counted under it" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(roster_entry(terms: [], from_history: false))
        invented = legislator.legislator_terms.find_by!(term_start_year: 2025)
        district_score = create(:legislator_district_score, legislator_term: invented)
        locale_score = create(:legislator_locale_score, legislator_term: invented)
        user_score = create(:user_legislator_term_score, legislator_term: invented)

        seed_entry!(roster_entry(terms: [house_term(2011, 2013)], current_member: false))

        expect(LegislatorTerm.where(id: invented.id)).to be_empty
        expect(LegislatorDistrictScore.where(id: district_score.id)).to be_empty
        expect(LegislatorLocaleScore.where(id: locale_score.id)).to be_empty
        expect(UserLegislatorTermScore.where(id: user_score.id)).to be_empty
        expect(legislator.legislator_terms.reload.pluck(:term_start_year)).to eq([2011])
      end
    end

    # @lat: [[seed-legislator-terms-score-rebuild#Retirement restores the scores of the terms a person keeps]]
    it "rebuilds the score rows for the terms that survive" do
      legislator = seed_entry!(roster_entry(terms: [house_term(2021, 2023), house_term(2023, 2025)]))
      legislator.legislator_terms.create!(
        term_start_year: 2025,
        term_end_year: 2027,
        district: District.find_by!(name: "FL20", sway_locale: congress)
      )
      reader = create(:user)
      reader_link = create(:user_legislator, user: reader, legislator: legislator, active: false)
      LegislatorDistrictScore.where(legislator_term_id: legislator.legislator_terms.ids).delete_all
      LegislatorLocaleScore.where(legislator_term_id: legislator.legislator_terms.ids).delete_all
      UserLegislatorTermScore.where(legislator_term_id: legislator.legislator_terms.ids).delete_all

      seed_entry!(roster_entry(terms: [house_term(2021, 2023), house_term(2023, 2025)], current_member: false))

      expect(legislator.legislator_terms.reload.pluck(:term_start_year)).to contain_exactly(2021, 2023)
      # Every surviving term, not just the one running today: an ended term is
      # what the History tab reads.
      legislator.legislator_terms.each do |term|
        expect(LegislatorDistrictScore.find_by(legislator_term: term)).not_to be_nil
        expect(LegislatorLocaleScore.find_by(legislator_term: term)).not_to be_nil
        expect(UserLegislatorTermScore.find_by(user_legislator: reader_link, legislator_term: term))
          .not_to be_nil
      end
    end

    it "keeps the person themselves, and every term the history does prove" do
      legislator = seed_entry!(roster_entry(terms: [house_term(2021, 2023), house_term(2023, 2025)]))
      legislator.legislator_terms.create!(
        term_start_year: 2025,
        term_end_year: 2027,
        district: District.find_by!(name: "FL20", sway_locale: congress)
      )

      seed_entry!(roster_entry(terms: [house_term(2021, 2023), house_term(2023, 2025)], current_member: false))

      expect(Legislator.find_by(external_id: "Q6VD001", sway_locale: congress)).to be_present
      expect(legislator.legislator_terms.reload.pluck(:term_start_year)).to contain_exactly(2021, 2023)
    end

    it "leaves every stored term alone when the list did not come from the history source" do
      travel_to(Time.utc(2026, 8, 6)) do
        legislator = seed_entry!(roster_entry(terms: [], from_history: false))

        seed_entry!(roster_entry(terms: [house_term(2011, 2013)], from_history: false))

        expect(legislator.legislator_terms.reload.pluck(:term_start_year)).to contain_exactly(2011, 2025)
      end
    end

    # An empty list is not evidence that every stored term was invented. It
    # means the entry arrived malformed, and acting on it would delete a
    # person's whole history.
    it "keeps every stored term when the proven list is empty" do
      legislator = seed_entry!(roster_entry(terms: [house_term(2021, 2023)]))

      seed_entry!(roster_entry(terms: [], current_member: false))

      expect(legislator.legislator_terms.reload.pluck(:term_start_year)).to eq([2021])
    end
  end

  # @lat: [[seed-legislator-terms-score-rebuild#Why the "knows every table" spec is a tripwire, not a behavior test]]
  it "knows every table that counts something under a term" do
    tables = ActiveRecord::Base.connection.tables.select { |table|
      ActiveRecord::Base.connection.columns(table).any? { |column| column.name == "legislator_term_id" }
    }

    expect(tables).to match_array(
      %w[legislator_district_scores legislator_locale_scores user_legislator_term_scores]
    ), "a table now points at legislator_terms that SeedLegislatorTerms#retire_unproven_terms! does not delete from"
  end

  # @lat: [[current-legislator-term#A term carries the day it really began]]
  describe "recording the day Sway first saw somebody in a seat" do
    let(:today) { Date.new(2026, 8, 6) }

    # ALL THREE HOLD.
    it "stamps the running term of a person this run created in a locale that had legislators" do
      travel_to(today) do
        legislator = seed_entry!(
          roster_entry(terms: [], from_history: false), locale_had_legislators: true
        )

        term = legislator.legislator_terms.sole
        expect(term.began_on).to eq(Date.new(2026, 8, 6))
        expect(term.began_on_source).to eq(LegislatorTerm::DateSource::OBSERVED)
      end
    end

    # THE LOCALE WAS EMPTY. A first seed of an empty database would otherwise
    # stamp every sitting member with today, which puts every past vote outside
    # every term. This is the clause that matters most.
    it "stamps nobody when the locale held no legislators before the run" do
      travel_to(today) do
        legislator = seed_entry!(roster_entry(terms: [], from_history: false))

        expect(legislator.legislator_terms.sole.began_on).to be_nil
      end
    end

    # THE PERSON WAS ALREADY STORED. The row is pre-created with NO term, so
    # the term below is still written this run — otherwise the example would
    # pass on a term that was never created.
    it "stamps nobody for a person the run found rather than created" do
      travel_to(today) do
        create(:legislator, sway_locale: congress, external_id: "Q6VD001")

        legislator = seed_entry!(
          roster_entry(terms: [], from_history: false), locale_had_legislators: true
        )

        expect(legislator.legislator_terms.sole.began_on).to be_nil
      end
    end

    # THE TERM IS NOT THE ONE RUNNING TODAY. A published history writes this
    # person's PAST terms in the same run, and stamping one would move every
    # vote counted under it outside every term.
    it "stamps only the running term, never the past ones written beside it" do
      travel_to(today) do
        legislator = seed_entry!(
          roster_entry(terms: [house_term(2021, 2023), house_term(2025, 2027)]),
          locale_had_legislators: true
        )

        expect(legislator.legislator_terms.order(:term_start_year).pluck(:term_start_year, :began_on))
          .to eq([[2021, nil], [2025, Date.new(2026, 8, 6)]])
      end
    end

    # A stamped start is what keeps the successor off their predecessor's
    # bills. Reading it back through the choke point every score goes through
    # is the whole point of writing it.
    it "keeps a bill decided before they arrived out of their term" do
      travel_to(today) do
        legislator = seed_entry!(
          roster_entry(terms: [], from_history: false), locale_had_legislators: true
        )

        expect(LegislatorTerm.covering(Date.new(2026, 3, 1), legislator: legislator)).to be_nil
        expect(LegislatorTerm.covering(Date.new(2026, 8, 6), legislator: legislator))
          .to eq(legislator.legislator_terms.sole)
      end
    end
  end

  # db:seed runs on every production boot, so runs two and later must change
  # nothing at all.
  it "changes nothing on a second run over the same entry" do
    entry = roster_entry(terms: [house_term(2021, 2023), house_term(2023, 2025)], current_member: false)
    legislator = seed_entry!(entry)
    before = legislator.legislator_terms.order(:term_start_year).map(&:attributes)

    seed_entry!(entry)
    legislator.legislator_terms.reload

    expect(legislator.legislator_terms.order(:term_start_year).map(&:attributes)).to eq(before)
  end

  # The example above cannot see the difference between "skipped the write
  # because nothing differs" and "wrote the same values again": update_columns
  # does not move updated_at, so the rows compare equal either way. Without this,
  # deleting the equality checks in #correct_terms! would break no test.
  it "writes nothing at all on a second run, rather than rewriting the same values" do
    entry = roster_entry(terms: [house_term(2021, 2023), house_term(2023, 2025)], current_member: false)
    seed_entry!(entry)

    expect_any_instance_of(LegislatorTerm).not_to receive(:update_columns)

    seed_entry!(entry)
  end

  describe "configured seats for curated seat-keyed rosters" do
    let(:baltimore) { create(:sway_locale, :baltimore) }
    let(:seat_chambers) do
      {
        "Mayor" => "Executive",
        "Council President" => "City Council",
        "Council Member" => "City Council"
      }
    end

    # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Persists a configured current office without claiming exact dates]]
    it "persists a configured current office without claiming exact dates" do
      travel_to(Date.new(2026, 10, 7)) do
        configure_seat_chambers!(baltimore, seat_chambers)
        entry = curated_seat_entry(
          title: "Council Member",
          office_key: "baltimore-district-1",
          district: "MD1"
        )
        legislator, prepared, district = curated_legislator_and_prepared(baltimore, entry)
        record_prepared_identity!(legislator, prepared)

        expect {
          described_class.new(legislator, prepared).call
        }.to change(Seat, :count).by(1)

        term = legislator.legislator_terms.sole
        expect(term).to be_current
        expect([term.term_start_year, term.term_end_year]).to eq([2024, 2028])
        expect(term.seat).to have_attributes(
          district_id: district.id,
          seat_identifier: "baltimore-district-1",
          title: "Council Member",
          chamber: "City Council"
        )
        expect([term.began_on, term.ended_on, term.began_on_source, term.ended_on_source])
          .to all(be_nil)

        described_class.new(legislator, prepared).call
        expect(Seat.where(district: district, seat_identifier: "baltimore-district-1").count).to eq(1)
      end
    end

    # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Waits for the actual current term window]]
    it "waits for the actual current term window before assigning a configured seat" do
      travel_to(Date.new(2024, 11, 1)) do
        configure_seat_chambers!(baltimore, seat_chambers)
        entry = curated_seat_entry(
          title: "Council Member",
          office_key: "baltimore-district-1",
          district: "MD1"
        )
        legislator, prepared, = curated_legislator_and_prepared(baltimore, entry)
        record_prepared_identity!(legislator, prepared)

        described_class.new(legislator, prepared).call

        term = legislator.legislator_terms.sole
        expect(prepared.current_member?).to be(true)
        expect(term).not_to be_current
        expect(term.seat).to be_nil
        expect(Seat.where(seat_identifier: "baltimore-district-1")).to be_empty
      end
    end

    # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Skips inactive prepared entries]]
    it "does not assign a seat from an inactive prepared entry" do
      travel_to(Date.new(2026, 10, 7)) do
        configure_seat_chambers!(baltimore, seat_chambers)
        entry = curated_seat_entry(
          title: "Council Member",
          office_key: "baltimore-district-1",
          district: "MD1"
        ).merge("active" => false)
        legislator, prepared, district = curated_legislator_and_prepared(baltimore, entry)
        record_prepared_identity!(legislator, prepared)
        term = create(
          :legislator_term,
          legislator: legislator,
          district: district,
          title: prepared.title,
          term_start_year: prepared.term_start_year,
          term_end_year: prepared.term_end_year
        )

        described_class.new(legislator, prepared).call

        expect(prepared.current_member?).to be(false)
        expect(term.reload.seat).to be_nil
        expect(Seat.where(seat_identifier: "baltimore-district-1")).to be_empty
      end
    end

    # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Rejects a cross-locale prepared district before writes]]
    it "rejects a cross-locale prepared district before creating terms or seats" do
      configure_seat_chambers!(baltimore, seat_chambers)
      entry = curated_seat_entry(
        title: "Council Member",
        office_key: "baltimore-district-1",
        district: "MD1"
      )
      legislator, prepared, = curated_legislator_and_prepared(baltimore, entry)
      foreign_locale = create(:sway_locale, city: "elsewhere", state: "Maryland", country: "United States")
      foreign_district = create(:district, sway_locale: foreign_locale, name: "MD1")
      prepared.define_singleton_method(:district) { foreign_district }
      record_prepared_identity!(legislator, prepared)

      expect {
        described_class.new(legislator, prepared).call
      }.to raise_error(Seats::UnresolvedSeatError, /prepared district.*different locale/i)
      expect(legislator.legislator_terms).to be_empty
      expect(Seat.where(seat_identifier: "baltimore-district-1")).to be_empty
    end

    # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Refuses an unmapped title and malformed office key]]
    it "refuses a configured title without chamber metadata and a malformed office key" do
      configure_seat_chambers!(baltimore, {"Mayor" => "Executive"})
      entry = curated_seat_entry(
        title: "Council Member",
        office_key: "baltimore-district-1",
        district: "MD1"
      )
      legislator, prepared, = curated_legislator_and_prepared(baltimore, entry)
      record_prepared_identity!(legislator, prepared)

      expect {
        described_class.new(legislator, prepared).call
      }.to raise_error(Seats::UnresolvedSeatError, /no configured chamber/i)
      expect(legislator.legislator_terms).to be_empty

      configure_seat_chambers!(baltimore, seat_chambers)
      malformed_identity = LegislatorIdentity.new(
        source: LegislatorIdentity::SEAT_AND_NAME,
        value: "missing-office-separator"
      )
      malformed_legislator, malformed_prepared, = curated_legislator_and_prepared(
        baltimore,
        entry,
        identity: malformed_identity
      )
      record_prepared_identity!(malformed_legislator, malformed_prepared)

      expect {
        described_class.new(malformed_legislator, malformed_prepared).call
      }.to raise_error(Seats::UnresolvedSeatError, /does not contain a configured office identity/)
      expect(malformed_legislator.legislator_terms).to be_empty
    end

    # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Requires the prepared identity to belong to the legislator]]
    it "requires the prepared locale identity to resolve to this legislator" do
      configure_seat_chambers!(baltimore, seat_chambers)
      entry = curated_seat_entry(
        title: "Council Member",
        office_key: "baltimore-district-1",
        district: "MD1"
      )
      legislator, prepared, = curated_legislator_and_prepared(baltimore, entry)
      wrong_legislator = create(
        :legislator,
        sway_locale: baltimore,
        external_id: "wrong-identity-owner",
        first_name: "Taylor",
        last_name: "Seat"
      )
      record_prepared_identity!(wrong_legislator, prepared)

      expect {
        described_class.new(legislator, prepared).call
      }.to raise_error(Seats::UnresolvedSeatError, /does not identify this legislator/)
      expect(legislator.legislator_terms).to be_empty
      expect(wrong_legislator.legislator_terms).to be_empty
    end

    # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Repairs only a matching current nil-seat term]]
    it "repairs only a matching current nil-seat term and preserves historical civic rows" do
      travel_to(Date.new(2026, 10, 7)) do
        configure_seat_chambers!(baltimore, seat_chambers)
        entry = curated_seat_entry(
          title: "Council Member",
          office_key: "baltimore-district-1",
          district: "MD1"
        )
        legislator, prepared, district = curated_legislator_and_prepared(baltimore, entry)
        record_prepared_identity!(legislator, prepared)
        historical = create(
          :legislator_term,
          legislator: legislator,
          district: district,
          title: "Council Member",
          term_start_year: 2020,
          term_end_year: 2024,
          began_on: Date.new(2020, 12, 3),
          began_on_source: LegislatorTerm::DateSource::PUBLISHED,
          ended_on: Date.new(2024, 12, 5),
          ended_on_source: LegislatorTerm::DateSource::PUBLISHED
        )
        current = create(
          :legislator_term,
          legislator: legislator,
          district: district,
          title: "Council Member",
          term_start_year: prepared.term_start_year,
          term_end_year: prepared.term_end_year,
          began_on: Date.new(2024, 12, 5),
          began_on_source: LegislatorTerm::DateSource::PUBLISHED,
          ended_on: Date.new(2028, 12, 7),
          ended_on_source: LegislatorTerm::DateSource::PUBLISHED
        )
        bill = create(:bill, sway_locale: baltimore)
        vote = create(:legislator_vote, bill: bill, legislator: legislator, legislator_term: current)
        score = create(:legislator_district_score, legislator_term: current, count_agreed: 4)
        historical_before = historical.attributes
        vote_before = vote.attributes
        score_before = score.attributes
        current_before = current.attributes.except("seat_id", "updated_at")

        described_class.new(legislator, prepared).call

        current.reload
        expect(current.seat).to have_attributes(
          seat_identifier: "baltimore-district-1",
          title: "Council Member",
          chamber: "City Council"
        )
        expect(current.attributes.except("seat_id", "updated_at")).to eq(current_before)
        expect(historical.reload.attributes).to eq(historical_before)
        expect(vote.reload.attributes).to eq(vote_before)
        expect(score.reload.attributes).to eq(score_before)
      end
    end

    # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Preserves a seat assigned after selection]]
    it "preserves a seat assigned after the current term is selected" do
      travel_to(Date.new(2026, 10, 7)) do
        configure_seat_chambers!(baltimore, seat_chambers)
        entry = curated_seat_entry(
          title: "Council Member",
          office_key: "baltimore-district-1",
          district: "MD1"
        )
        legislator, prepared, district = curated_legislator_and_prepared(baltimore, entry)
        record_prepared_identity!(legislator, prepared)
        term = create(
          :legislator_term,
          legislator: legislator,
          district: district,
          title: prepared.title,
          term_start_year: prepared.term_start_year,
          term_end_year: prepared.term_end_year
        )
        concurrent_seat = Seat.create!(
          district: district,
          seat_identifier: "baltimore-district-2",
          title: prepared.title,
          chamber: "City Council"
        )

        competing_write_done = false
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*_args, payload|
          next if competing_write_done
          next unless payload[:name] == "LegislatorTerm Load"
          next unless payload[:sql].include?('FROM "legislator_terms"') && payload[:sql].include?('"legislator_terms"."legislator_id"')
          next unless payload[:sql].include?("legislator_terms.began_on") && payload[:sql].include?("legislator_terms.ended_on")

          competing_write_done = true
          LegislatorTerm.where(id: term.id).update_all(seat_id: concurrent_seat.id)
        end

        begin
          begin
            described_class.new(legislator, prepared).call
          rescue Seats::UnresolvedSeatError
            nil
          end
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end

        expect(competing_write_done).to be(true)
        expect(term.reload.seat).to eq(concurrent_seat)
        expect(Seat.where(seat_identifier: "baltimore-district-1")).to be_empty
      end
    end

    # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Refuses mismatched current metadata and a conflicting persisted seat]]
    it "refuses mismatched current metadata and a conflicting persisted seat" do
      travel_to(Date.new(2026, 10, 7)) do
        configure_seat_chambers!(baltimore, seat_chambers)
        entry = curated_seat_entry(
          title: "Council Member",
          office_key: "baltimore-district-1",
          district: "MD1"
        )
        legislator, prepared, district = curated_legislator_and_prepared(baltimore, entry)
        record_prepared_identity!(legislator, prepared)
        mismatched = create(
          :legislator_term,
          legislator: legislator,
          district: district,
          title: "Council President",
          term_start_year: prepared.term_start_year,
          term_end_year: prepared.term_end_year
        )

        expect {
          described_class.new(legislator, prepared).call
        }.to raise_error(Seats::UnresolvedSeatError, /does not match the prepared current term/)
        expect(mismatched.reload.seat).to be_nil

        mismatched.update!(title: "Council Member")
        other_seat = Seat.create!(
          district: district,
          seat_identifier: "baltimore-district-2",
          title: "Council Member",
          chamber: "City Council"
        )
        mismatched.update!(seat: other_seat)

        expect {
          described_class.new(legislator, prepared).call
        }.to raise_error(Seats::UnresolvedSeatError, /conflicts with the prepared office identity/)
        expect(mismatched.reload.seat).to eq(other_seat)
      end
    end
  end

  describe "configured seats for person-keyed rosters" do
    let(:congress) { create(:sway_locale, :congress) }
    let(:seat_chambers) do
      {
        "Sen." => "Senate",
        "Rep." => "House of Representatives"
      }
    end

    # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Attaches distinct seats for House and co-serving Senators]]
    it "attaches distinct seats for House and co-serving Senators and preserves idempotency" do
      travel_to(Date.new(2025, 6, 1)) do
        configure_seat_chambers!(congress, seat_chambers)
        district_md3 = create(:district, sway_locale: congress, name: "MD3")
        district_md0 = create(:district, sway_locale: congress, name: "MD0")

        house_entry = {
          "bioguideId" => "H001234",
          "name" => "House, Rep",
          "state" => "Maryland",
          "district" => 3,
          "currentMember" => true,
          "termsSource" => "unitedstates/congress-legislators",
          "terms" => {
            "item" => [
              {
                "chamber" => "House of Representatives",
                "startYear" => 2025,
                "endYear" => 2027,
                "beganOn" => "2025-01-03",
                "endedOn" => "2027-01-03",
                "stateCode" => "MD",
                "district" => 3
              }
            ]
          }
        }
        rep_preparer = SeedPreparers::Legislators::CongressDotGov.new(house_entry, congress)
        rep_legislator = create(
          :legislator,
          district: district_md3,
          sway_locale: congress,
          external_id: "H001234",
          first_name: "Rep",
          last_name: "House"
        )
        record_prepared_identity!(rep_legislator, rep_preparer)

        sen1_entry = {
          "bioguideId" => "S000001",
          "name" => "Sen1, One",
          "state" => "Maryland",
          "currentMember" => true,
          "termsSource" => "unitedstates/congress-legislators",
          "terms" => {
            "item" => [
              {
                "chamber" => "Senate",
                "startYear" => 2025,
                "endYear" => 2031,
                "beganOn" => "2025-01-03",
                "endedOn" => "2031-01-03",
                "stateCode" => "MD",
                "class" => 1
              }
            ]
          }
        }
        sen1_preparer = SeedPreparers::Legislators::CongressDotGov.new(sen1_entry, congress)
        sen1_legislator = create(
          :legislator,
          district: district_md0,
          sway_locale: congress,
          external_id: "S000001",
          first_name: "One",
          last_name: "Sen1"
        )
        record_prepared_identity!(sen1_legislator, sen1_preparer)

        sen3_entry = {
          "bioguideId" => "S000003",
          "name" => "Sen3, Three",
          "state" => "Maryland",
          "currentMember" => true,
          "termsSource" => "unitedstates/congress-legislators",
          "terms" => {
            "item" => [
              {
                "chamber" => "Senate",
                "startYear" => 2023,
                "endYear" => 2029,
                "beganOn" => "2023-01-03",
                "endedOn" => "2029-01-03",
                "stateCode" => "MD",
                "class" => 3
              }
            ]
          }
        }
        sen3_preparer = SeedPreparers::Legislators::CongressDotGov.new(sen3_entry, congress)
        sen3_legislator = create(
          :legislator,
          district: district_md0,
          sway_locale: congress,
          external_id: "S000003",
          first_name: "Three",
          last_name: "Sen3"
        )
        record_prepared_identity!(sen3_legislator, sen3_preparer)

        described_class.new(rep_legislator, rep_preparer).call
        described_class.new(sen1_legislator, sen1_preparer).call
        described_class.new(sen3_legislator, sen3_preparer).call

        term_rep = rep_legislator.legislator_terms.sole
        expect(term_rep.seat).to have_attributes(
          district_id: district_md3.id,
          seat_identifier: "md-house-district-3",
          title: "Rep.",
          chamber: "House of Representatives"
        )

        term_sen1 = sen1_legislator.legislator_terms.sole
        expect(term_sen1.seat).to have_attributes(
          district_id: district_md0.id,
          seat_identifier: "md-senate-class-1",
          title: "Sen.",
          chamber: "Senate"
        )

        term_sen3 = sen3_legislator.legislator_terms.sole
        expect(term_sen3.seat).to have_attributes(
          district_id: district_md0.id,
          seat_identifier: "md-senate-class-3",
          title: "Sen.",
          chamber: "Senate"
        )

        expect(term_sen1.seat_id).not_to eq(term_sen3.seat_id)
        expect(Seat.where(district: district_md0).count).to eq(2)
        expect(Seat.where(district: district_md3).count).to eq(1)

        # Idempotency check: second run makes zero writes
        expect {
          described_class.new(rep_legislator, rep_preparer).call
          described_class.new(sen1_legislator, sen1_preparer).call
          described_class.new(sen3_legislator, sen3_preparer).call
        }.not_to change(Seat, :count)

        expect(term_rep.reload.seat.seat_identifier).to eq("md-house-district-3")
        expect(term_sen1.reload.seat.seat_identifier).to eq("md-senate-class-1")
        expect(term_sen3.reload.seat.seat_identifier).to eq("md-senate-class-3")
      end
    end

    # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Attaches distinct seats for Maryland executives, senators, and delegates]]
    it "attaches distinct seats for Maryland executives, senators, and delegates and preserves idempotency" do
      travel_to(Date.new(2025, 6, 1)) do
        maryland = create(:sway_locale, :maryland)
        SeedLegislator.run([maryland])

        expect(maryland.legislators.count).to eq(189)
        terms = LegislatorTerm.where(legislator: maryland.legislators)
        expect(terms.count).to eq(189)
        expect(terms.where(seat_id: nil)).to be_empty

        seats = Seat.where(id: terms.select(:seat_id))
        expect(seats.count).to eq(189)
        expect(seats.pluck(:seat_identifier).uniq.count).to eq(189)

        gov = maryland.legislators.find_by!(last_name: "Moore")
        expect(gov.legislator_terms.first.seat).to have_attributes(
          seat_identifier: "md-governor-0",
          title: "Governor",
          chamber: "Executive"
        )

        expect(maryland.legislators.find_by(first_name: "Aruna", last_name: "Miller")).to be_nil
        expect(maryland.legislators.find_by(external_id: "ocd-person/1ad81709-e1d6-42bd-86bc-afdec934288c")).to be_nil
        expect(seats.where(seat_identifier: %w[md-lt-governor-0 md-attorney-general-0])).to be_empty

        del_44a = maryland.legislators.find_by!(last_name: "Ebersole")
        expect(del_44a.legislator_terms.first.seat).to have_attributes(
          seat_identifier: "md-delegate-44a",
          title: "Delegate",
          chamber: "House of Delegates"
        )

        dels_44b = maryland.legislators.where(last_name: ["McCaskill", "Ruth"]).to_a
        expect(dels_44b.map { |d| d.legislator_terms.first.seat.seat_identifier }).to contain_exactly(
          "md-delegate-44b-1",
          "md-delegate-44b-2"
        )

        sen_46 = maryland.legislators.find_by!(last_name: "Ferguson")
        expect(sen_46.legislator_terms.first.seat).to have_attributes(
          seat_identifier: "md-senator-46",
          title: "Senator",
          chamber: "Senate"
        )

        dels_46 = maryland.legislators.where(last_name: ["Clippinger", "Edelson", "Lewis"]).to_a
        expect(dels_46.map { |d| d.legislator_terms.first.seat.seat_identifier }).to contain_exactly(
          "md-delegate-46-1",
          "md-delegate-46-2",
          "md-delegate-46-3"
        )

        expect {
          SeedLegislator.run([maryland])
        }.not_to change(Seat, :count)
      end
    end
  end

  describe "filling a missing term title from official evidence" do
    let(:maryland) { create(:sway_locale, :maryland) }
    let(:district) { create(:district, sway_locale: maryland, name: "District 43A") }
    let(:legislator) { create(:legislator, sway_locale: maryland, external_id: "ocd-person/12345") }
    let(:identity) { LegislatorIdentity.from_published_id(LegislatorIdentity::OPENSTATES, legislator.external_id) }

    def blank_term(legislator:, district:, start_date: Date.new(2023, 1, 11), end_date: Date.new(2027, 1, 13), title: nil,
      seat_identifier: "md-house-43a")
      seat = Seat.create!(district: district, seat_identifier: seat_identifier, title: "Delegate", chamber: "House")
      term = create(
        :legislator_term,
        legislator: legislator,
        district: district,
        seat: seat,
        term_start_year: start_date.year,
        term_end_year: end_date.year,
        began_on: start_date,
        began_on_source: LegislatorTerm::DateSource::PUBLISHED,
        ended_on: end_date,
        ended_on_source: LegislatorTerm::DateSource::PUBLISHED,
        title: title
      )
      LegislatorIdentifier.record!(legislator: legislator, identity: identity)
      term
    end

    # @lat: [[seed-legislator-title-tests#Existing term title fill#Fills an exact supported title]]
    it "fills an existing blank title only from an exact supported matching fact" do
      term = blank_term(legislator: legislator, district: district)
      prepared = supported_service_prepared(
        records: [service_record], district: district, sway_locale: maryland
      )
      attrs_before_fill = term.attributes.except("title", "updated_at")

      expect {
        described_class.new(legislator, prepared).call
      }.to change { term.reload.title }.from(nil).to("Delegate")
      expect(term.attributes.except("title", "updated_at")).to eq(attrs_before_fill)
    end

    # @lat: [[seed-legislator-title-tests#Existing term title fill#Preserves the term except for its title]]
    it "preserves nonblank titles and makes no second title write" do
      term = blank_term(legislator: legislator, district: district)
      prepared = supported_service_prepared(
        records: [service_record], district: district, sway_locale: maryland
      )
      described_class.new(legislator, prepared).call
      term.reload
      attrs_after_fill = term.attributes.except("title", "updated_at")

      expect_any_instance_of(LegislatorTerm).not_to receive(:update_columns)
      described_class.new(legislator, prepared).call
      expect(term.reload.title).to eq("Delegate")
      expect(term.attributes.except("title", "updated_at")).to eq(attrs_after_fill)
    end

    # @lat: [[seed-legislator-title-tests#Existing term title fill#Preserves a nonblank title]]
    it "does not fill a nonblank title from stale official evidence" do
      term = blank_term(legislator: legislator, district: district, title: "Senator")
      prepared = supported_service_prepared(
        records: [service_record(title: "Delegate")], district: district, sway_locale: maryland
      )

      expect {
        described_class.new(legislator, prepared).call
      }.not_to change { term.reload.title }
    end

    # @lat: [[seed-legislator-title-tests#Existing term title fill#Rejects unsupported or mismatched facts]]
    it "leaves a blank title unchanged for unsupported or mismatched facts" do
      term = blank_term(legislator: legislator, district: district)
      cases = [
        [service_record(identity_value: "ocd-person/other"), district],
        [service_record(office_identity: "md-senate-43"), district],
        [service_record, create(:district, sway_locale: maryland, name: "District 43B")],
        [service_record(start_date: "2019-01-09"), district],
        [service_record(end_date: "2025-01-08"), district]
      ]

      cases.each do |record, fact_district|
        prepared = supported_service_prepared(
          records: [record], district: fact_district, sway_locale: maryland
        )
        expect {
          described_class.fill_missing_title!(term, prepared:)
        }.not_to change { term.reload.title }
      end
    end
  end

  describe "creating an official service term" do
    let(:maryland) { create(:sway_locale, :maryland) }
    let(:district) { create(:district, sway_locale: maryland, name: "District 43A") }
    let(:legislator) { create(:legislator, sway_locale: maryland, external_id: "ocd-person/12345") }
    let(:identity) { LegislatorIdentity.from_published_id(LegislatorIdentity::OPENSTATES, legislator.external_id) }

    # @lat: [[seed-legislator-title-tests#New term seat mapping#Persists the official interval and seat]]
    it "persists a supported exact interval and source-identified seat on a new term" do
      prepared = supported_service_prepared(
        records: [service_record], district: district, sway_locale: maryland
      )
      LegislatorIdentifier.record!(legislator: legislator, identity: identity)

      SeedLegislatorTerms.new(legislator, prepared).call

      term = legislator.legislator_terms.sole
      expect([term.began_on, term.ended_on]).to eq([Date.new(2023, 1, 11), Date.new(2027, 1, 13)])
      expect([term.began_on_source, term.ended_on_source]).to all(eq(LegislatorTerm::DateSource::PUBLISHED))
      expect([term.seat.seat_identifier, term.seat.title, term.seat.chamber]).to eq(["md-house-43a", "Delegate", "House"])
    end

    # @lat: [[seed-legislator-title-tests#New term seat mapping#Refuses mismatched official identity]]
    it "does not create a service term without the matching scheme-qualified person identity" do
      prepared = supported_service_prepared(
        records: [service_record(identity_value: "ocd-person/other")], district: district, sway_locale: maryland
      )

      expect { SeedLegislatorTerms.new(legislator, prepared).call }
        .not_to change(LegislatorTerm, :count)
    end
  end

  describe "filling existing titles from one official service result" do
    let(:maryland) { create(:sway_locale, :maryland) }
    let(:district) { create(:district, sway_locale: maryland, name: "District 43A") }
    let(:legislator) { create(:legislator, sway_locale: maryland, external_id: "ocd-person/12345") }
    let(:identity) { LegislatorIdentity.from_published_id(LegislatorIdentity::OPENSTATES, legislator.external_id) }

    # @lat: [[seed-legislator-title-tests#Executive title caller#Uses a supplied locale result once]]
    it "fills one exact blank term from the supplied result without refetching" do
      term = create(
        :legislator_term,
        legislator: legislator,
        district: district,
        seat: Seat.create!(district: district, seat_identifier: "md-house-43a", title: "Delegate", chamber: "House"),
        term_start_year: 2023,
        term_end_year: 2027,
        began_on: Date.new(2023, 1, 11),
        began_on_source: LegislatorTerm::DateSource::PUBLISHED,
        ended_on: Date.new(2027, 1, 13),
        ended_on_source: LegislatorTerm::DateSource::PUBLISHED,
        title: nil
      )
      LegislatorIdentifier.record!(legislator: legislator, identity: identity)
      result = official_service_result(records: [service_record], sway_locale: maryland)

      expect(Legislation::Adapters::GenericRosterAdapter).not_to receive(:new)
      expect { ExecutiveTitleFillService.new(maryland, official_service_result: result).call }
        .to change { term.reload.title }.from(nil).to("Delegate")
    end

    # @lat: [[seed-legislator-title-tests#Executive title caller#Rejects duplicate exact facts]]
    it "leaves the title blank when the official result has duplicate exact facts" do
      term = create(
        :legislator_term,
        legislator: legislator,
        district: district,
        seat: Seat.create!(district: district, seat_identifier: "md-house-43a", title: "Delegate", chamber: "House"),
        term_start_year: 2023,
        term_end_year: 2027,
        began_on: Date.new(2023, 1, 11),
        began_on_source: LegislatorTerm::DateSource::PUBLISHED,
        ended_on: Date.new(2027, 1, 13),
        ended_on_source: LegislatorTerm::DateSource::PUBLISHED,
        title: nil
      )
      LegislatorIdentifier.record!(legislator: legislator, identity: identity)
      result = official_service_result(records: [service_record, service_record(title: "Senator")], sway_locale: maryland)

      expect { ExecutiveTitleFillService.new(maryland, official_service_result: result).call }
        .not_to change { term.reload.title }
    end
  end
end
