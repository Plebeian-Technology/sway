# frozen_string_literal: true

require "rails_helper"
require "support/open_legislator_fixture_helpers"

RSpec.describe GenericLegislatorVoteUpdateService do
  include OpenLegislatorFixtureHelpers

  let(:sway_locale) { create(:sway_locale, :congress) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let!(:voter) { create(:legislator, district: district, external_id: "VOTER_1") }
  before do
    @sponsor = create(:legislator, district: district, external_id: "SPONSOR_1")
    @cosponsor = create(:legislator, district: district, external_id: "COSPONSOR_1")
    cycle_start = TermWindow.cycle_start_year(sway_locale, Date.current)
    @voter_term = create(:legislator_term, legislator: voter, district: district,
      term_start_year: cycle_start, term_end_year: cycle_start + 2)
    create(:legislator_term, legislator: @sponsor, district: district,
      term_start_year: cycle_start, term_end_year: cycle_start + 2)
    create(:legislator_term, legislator: @cosponsor, district: district,
      term_start_year: cycle_start, term_end_year: cycle_start + 2)
  end

  let(:bill) do
    b = create(:bill, sway_locale: sway_locale, legislator: @sponsor)
    create(:bill_cosponsor, bill: b, legislator: @cosponsor)
    b
  end

  subject(:service) { described_class.new(bill) }

  describe "#call" do
    context "when votes payload is empty" do
      it "infers votes from primary sponsor and cosponsors" do
        result = service.call(votes: [])

        expect(result.inferred).to be true
        expect(LegislatorVote.where(bill: bill, legislator: @sponsor, inferred: true).count).to eq(1)
        expect(LegislatorVote.where(bill: bill, legislator: @cosponsor, inferred: true).count).to eq(1)
        expect(LegislatorVote.find_by(bill: bill, legislator: @sponsor).support).to eq("FOR")
      end

      it "does not infer votes when infer_sponsors_if_empty is false" do
        result = service.call(votes: [], infer_sponsors_if_empty: false)

        expect(result.inferred).to be false
        expect(LegislatorVote.where(bill: bill).count).to eq(0)
      end
    end

    context "when normalized votes payload is provided" do
      before do
        @test_votes = [
          {
            legislator_external_id: "VOTER_1",
            vote_value: "yea",
            voted_on: Date.current,
            chamber: "house"
          }
        ]
      end

      it "creates a LegislatorVote record for the matched legislator" do
        result = service.call(votes: @test_votes)

        expect(result.written_count).to eq(1)
        expect(result.unmatched_count).to eq(0)
        expect(result.inferred).to be false

        lv = LegislatorVote.find_by(bill: bill, legislator: voter)
        expect(lv).to be_present
        expect(lv.support).to eq("FOR")
        expect(lv.inferred).to be false
      end

      it "updates existing vote if support changes" do
        create(:legislator_vote, bill: bill, legislator: voter, legislator_term: @voter_term, support: "AGAINST", source: "congress")

        service.call(votes: @test_votes)

        lv = LegislatorVote.find_by(bill: bill, legislator: voter)
        expect(lv.support).to eq("FOR")
      end

      it "does not overwrite an admin's manual edit" do
        create(:legislator_vote, bill: bill, legislator: voter, legislator_term: @voter_term, support: "AGAINST", source: "manual")

        service.call(votes: @test_votes)

        lv = LegislatorVote.find_by(bill: bill, legislator: voter)
        expect(lv.support).to eq("AGAINST")
        expect(lv.source).to eq("manual")
      end
    end

    context "when a voter cannot be resolved" do
      it "records unmatched count and logs a warning without raising an error" do
        unmatched_payload = [
          {
            legislator_external_id: "UNKNOWN_ID",
            vote_value: "nay",
            voted_on: Date.current
          }
        ]

        expect(SwayLogging).to receive(:warn).with("generic_legislator_votes.voters_not_matched", any_args)

        result = service.call(votes: unmatched_payload)

        expect(result.written_count).to eq(0)
        expect(result.unmatched_count).to eq(1)
      end
    end

    # @lat: [[legislator-vote-upserter-guard-rules#Why LegislatorVoteUpserter guards writes the way it does]]
    context "when no term covers the bill's date for a matched voter" do
      it "writes nothing and counts nothing as written" do
        unseated = create(:legislator, district: district, external_id: "UNSEATED_1")

        result = service.call(votes: [
          {legislator_id: unseated.id, vote_value: "yea", voted_on: Date.current}
        ])

        expect(result.written_count).to eq(0)
        expect(result.unmatched_count).to eq(0)
        expect(LegislatorVote.where(bill: bill, legislator: unseated).count).to eq(0)
      end
    end

    context "when integrating with GenericVoteAdapter empty results" do
      it "infers votes from sponsors without logging unmatched voter warnings" do
        expect(SwayLogging).not_to receive(:warn).with("generic_legislator_votes.voters_not_matched", any_args)

        result = service.call(votes: [], infer_sponsors_if_empty: true)

        expect(result.inferred).to be true
        expect(result.written_count).to eq(0)
        expect(result.unmatched_count).to eq(0)
        expect(LegislatorVote.where(bill: bill, inferred: true).count).to eq(2)
      end

      it "safely ignores nil or empty hash items in vote payloads" do
        corrupt_votes = [
          nil,
          {},
          {legislator_external_id: "VOTER_1", vote_value: "yea", voted_on: Date.current}
        ]

        result = service.call(votes: corrupt_votes)

        expect(result.written_count).to eq(1)
        expect(result.unmatched_count).to eq(0)
        lv = LegislatorVote.find_by(bill: bill, legislator: voter)
        expect(lv).to be_present
        expect(lv.support).to eq("FOR")
      end
    end

    context "legacy vote_source decoupling" do
      it "reads service_source from vote_rules without calling vote_source" do
        rules = instance_double(
          SwayLocale::JurisdictionRules,
          vote_rules: {engine: "open_states"}
        )
        allow(sway_locale).to receive(:jurisdiction_rules).and_return(rules)

        service.call(votes: [
          {
            legislator_external_id: "VOTER_1",
            vote_value: "yea",
            voted_on: Date.current
          }
        ])

        lv = LegislatorVote.find_by(bill: bill, legislator: voter)
        expect(lv.source).to eq("open_states")
      end
    end
  end

  describe ".call" do
    it "instantiates and calls the service directly" do
      result = described_class.call(
        bill: bill,
        votes: [
          {
            legislator_external_id: "VOTER_1",
            vote_value: "nay",
            voted_on: Date.current
          }
        ]
      )

      expect(result.written_count).to eq(1)
      lv = LegislatorVote.find_by(bill: bill, legislator: voter)
      expect(lv.support).to eq("AGAINST")
    end
  end

  describe "decoupled retrieval and client isolation (TASK-ok5ox.48)" do
    describe "#service_source" do
      it "prioritizes retrieval over engine in vote_rules" do
        rules = instance_double(
          SwayLocale::JurisdictionRules,
          vote_rules: {retrieval: "open_states", engine: "generic_rest"}
        )
        allow(sway_locale).to receive(:jurisdiction_rules).and_return(rules)

        service.call(votes: [
          {
            legislator_external_id: "VOTER_1",
            vote_value: "yea",
            voted_on: Date.current
          }
        ])

        lv = LegislatorVote.find_by(bill: bill, legislator: voter)
        expect(lv.source).to eq("open_states")
      end

      it "maps congress_dot_gov retrieval to congress source" do
        rules = instance_double(
          SwayLocale::JurisdictionRules,
          vote_rules: {retrieval: "congress_dot_gov", engine: "legacy_engine"}
        )
        allow(sway_locale).to receive(:jurisdiction_rules).and_return(rules)

        service.call(votes: [
          {
            legislator_external_id: "VOTER_1",
            vote_value: "yea",
            voted_on: Date.current
          }
        ])

        lv = LegislatorVote.find_by(bill: bill, legislator: voter)
        expect(lv.source).to eq("congress")
      end
    end

    describe "#should_apply_final_passage?" do
      it "returns true when retrieval_for(:vote) returns legistar" do
        rules = instance_double(
          SwayLocale::JurisdictionRules,
          retrieval_for: "legistar",
          vote_rules: {},
          final_passage_action_ids: []
        )
        allow(bill.sway_locale).to receive(:jurisdiction_rules).and_return(rules)

        expect(service.send(:should_apply_final_passage?)).to be true
      end

      it "returns true when vote_rules has retrieval set to legistar" do
        rules = instance_double(
          SwayLocale::JurisdictionRules,
          retrieval_for: nil,
          vote_rules: {retrieval: "legistar"},
          final_passage_action_ids: []
        )
        allow(bill.sway_locale).to receive(:jurisdiction_rules).and_return(rules)

        expect(service.send(:should_apply_final_passage?)).to be true
      end
    end

    describe "#legistar_client" do
      it "raises ArgumentError when client is not configured, with zero fallback to baltimore" do
        rules = instance_double(
          SwayLocale::JurisdictionRules,
          vote_rules: {retrieval: "legistar"},
          legislation_rules: {}
        )
        allow(bill.sway_locale).to receive(:jurisdiction_rules).and_return(rules)
        allow(bill.sway_locale).to receive(:city).and_return(nil)

        expect {
          service.send(:legistar_client)
        }.to raise_error(ArgumentError, /No client configured for Legistar vote update/)
      end

      it "resolves client from vote_rules client property" do
        rules = instance_double(
          SwayLocale::JurisdictionRules,
          vote_rules: {client: "philly"},
          legislation_rules: {}
        )
        allow(bill.sway_locale).to receive(:jurisdiction_rules).and_return(rules)

        client = service.send(:legistar_client)
        expect(client.client).to eq("philly")
      end
    end
  end

  describe "timezone casting (TASK-wthd8.12)" do
    context "when timezone is configured in vote_rules" do
      before do
        @rules = instance_double(
          SwayLocale::JurisdictionRules,
          vote_timezone: "America/New_York",
          vote_rules: {timezone: "America/New_York"}
        )
        allow(sway_locale).to receive(:jurisdiction_rules).and_return(@rules)
      end

      it "converts late evening UTC timestamps to the local calendar day" do
        utc_timestamp = "2026-03-01T02:30:00Z"
        resolved_date = service.send(:resolve_vote_date, utc_timestamp)

        expect(resolved_date).to eq(Date.new(2026, 2, 28))
      end

      it "parses YYYY-MM-DD date strings via Date.iso8601 without shifting days" do
        date_str = "2026-03-01"
        resolved_date = service.send(:resolve_vote_date, date_str)

        expect(resolved_date).to eq(Date.new(2026, 3, 1))
      end

      it "supports arbitrary timezones without hardcoded locale strings" do
        pacific_rules = instance_double(
          SwayLocale::JurisdictionRules,
          vote_timezone: "America/Los_Angeles",
          vote_rules: {timezone: "America/Los_Angeles"}
        )
        allow(sway_locale).to receive(:jurisdiction_rules).and_return(pacific_rules)

        utc_timestamp = "2026-05-10T05:30:00Z"
        resolved_date = service.send(:resolve_vote_date, utc_timestamp)

        expect(resolved_date).to eq(Date.new(2026, 5, 9))
      end

      it "detects missing vote date and returns nil without falling back to Date.current" do
        expect(service.send(:resolve_vote_date, nil)).to be_nil
        expect(service.send(:resolve_vote_date, "")).to be_nil
        expect(service.send(:resolve_vote_date, "invalid-date")).to be_nil
      end

      it "falls back to UTC when vote_timezone is invalid" do
        rules = instance_double(
          SwayLocale::JurisdictionRules,
          vote_timezone: "Invalid/Zone_Name",
          vote_rules: {timezone: "Invalid/Zone_Name"}
        )
        allow(sway_locale).to receive(:jurisdiction_rules).and_return(rules)

        expect(service.send(:resolve_vote_date, "2026-03-15T03:30:00Z")).to eq(Date.new(2026, 3, 15))
      end
    end
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#The vote-entry roster is everyone who ever held the seat#Matching a name resolves against the roster of the vote's own day]]
  describe "historical official fallback (TASK-wthd8.11)" do
    before do
      @importer_instance = double("HistoricalElectedOfficialImporter")
      @importer_class = double("HistoricalElectedOfficialImporterClass")
      stub_const("HistoricalElectedOfficialImporter", @importer_class)
    end

    context "when enable_historical_fallback is enabled" do
      before do
        @rules = instance_double(
          SwayLocale::JurisdictionRules,
          enable_historical_fallback?: true,
          vote_timezone: "America/New_York",
          vote_rules: {enable_historical_fallback: true, timezone: "America/New_York"}
        )
        allow(sway_locale).to receive(:jurisdiction_rules).and_return(@rules)
      end

      it "invokes HistoricalElectedOfficialImporter and retries matching once when importer succeeds" do
        allow(@importer_class).to receive(:new).with(sway_locale: sway_locale).and_return(@importer_instance)

        vote_day = Date.new(2024, 1, 15)
        imported_legislator = nil
        expect(@importer_instance).to receive(:call).with(
          jurisdiction: sway_locale,
          identity_clues: hash_including(external_id: "HISTORICAL_1"),
          vote_day: vote_day
        ).once do
          imported_legislator = create(:legislator, district: district, external_id: "HISTORICAL_1")
          create(:legislator_term, legislator: imported_legislator, district: district,
            term_start_year: 2023, term_end_year: 2027)
          double("HistoricalElectedOfficialImporter::Result", success?: true, legislator: imported_legislator)
        end

        votes = [
          {
            legislator_external_id: "HISTORICAL_1",
            vote_value: "yea",
            voted_on: vote_day
          }
        ]

        result = service.call(votes: votes)
        expect(result.written_count).to eq(1)
        expect(result.unmatched_count).to eq(0)
        expect(LegislatorVote.find_by(bill: bill, legislator: imported_legislator)).to be_present
      end

      it "records voter as unmatched when historical importer fails" do
        allow(@importer_class).to receive(:new).with(sway_locale: sway_locale).and_return(@importer_instance)

        vote_day = Date.new(2024, 1, 15)
        fail_result = double("HistoricalElectedOfficialImporter::Result", success?: false)
        expect(@importer_instance).to receive(:call).with(
          jurisdiction: sway_locale,
          identity_clues: hash_including(external_id: "UNRESOLVABLE_ID"),
          vote_day: vote_day
        ).once.and_return(fail_result)

        votes = [
          {
            legislator_external_id: "UNRESOLVABLE_ID",
            vote_value: "yea",
            voted_on: vote_day
          }
        ]

        result = service.call(votes: votes)
        expect(result.written_count).to eq(0)
        expect(result.unmatched_count).to eq(1)
      end

      it "refreshes roster cache and resolves subsequent votes for the imported official without re-importing" do
        allow(@importer_class).to receive(:new).with(sway_locale: sway_locale).and_return(@importer_instance)
        vote_day = Date.new(2024, 6, 1)
        imported_official = nil

        expect(@importer_instance).to receive(:call).with(
          jurisdiction: sway_locale,
          identity_clues: hash_including(external_id: "HISTORICAL_RECOVERED"),
          vote_day: vote_day
        ).once do
          imported_official = create(:legislator, district: district, external_id: "HISTORICAL_RECOVERED")
          create(:legislator_term, legislator: imported_official, district: district,
            term_start_year: 2023, term_end_year: 2027)
          double("HistoricalElectedOfficialImporter::Result", success?: true, legislator: imported_official)
        end

        result = service.call(votes: [
          {legislator_external_id: "HISTORICAL_RECOVERED", vote_value: "yea", voted_on: vote_day},
          {legislator_external_id: "HISTORICAL_RECOVERED", vote_value: "yea", voted_on: vote_day}
        ])

        expect(result.written_count).to eq(2)
        expect(result.unmatched_count).to eq(0)
        expect(LegislatorVote.where(bill: bill, legislator: imported_official).count).to eq(1)
      end
    end

    context "when enable_historical_fallback is disabled" do
      before do
        @rules = instance_double(
          SwayLocale::JurisdictionRules,
          enable_historical_fallback?: false,
          vote_timezone: "America/New_York",
          vote_rules: {enable_historical_fallback: false, timezone: "America/New_York"}
        )
        allow(sway_locale).to receive(:jurisdiction_rules).and_return(@rules)
      end

      it "does not invoke HistoricalElectedOfficialImporter and records voter as unmatched" do
        expect(@importer_class).not_to receive(:new)

        votes = [
          {
            legislator_external_id: "UNKNOWN_ID",
            vote_value: "yea",
            voted_on: Date.new(2024, 1, 15)
          }
        ]

        result = service.call(votes: votes)
        expect(result.written_count).to eq(0)
        expect(result.unmatched_count).to eq(1)
      end
    end
  end

  describe "LegislativeVoteCoverage tracking (TASK-wthd8.8)" do
    before do
      @coverage_class = double("LegislativeVoteCoverage")
      stub_const("LegislativeVoteCoverage", @coverage_class)
    end

    it "records coverage with status complete on successful vote persistence" do
      expect(@coverage_class).to receive(:record_coverage!).with(
        bill: bill,
        chamber: bill.chamber,
        roll_call_number: anything,
        eligible_count: 1,
        matched_count: 1,
        unresolved_tokens: [],
        status: "complete"
      )

      service.call(votes: [
        {
          legislator_external_id: "VOTER_1",
          vote_value: "yea",
          voted_on: Date.current
        }
      ])
    end

    it "records coverage with status missing_vote_date when vote date is missing" do
      expect(@coverage_class).to receive(:record_coverage!).with(
        bill: bill,
        chamber: bill.chamber,
        roll_call_number: anything,
        eligible_count: 1,
        matched_count: 1,
        unresolved_tokens: [],
        status: "missing_vote_date"
      )

      bill.update!(house_vote_date_time_utc: nil, senate_vote_date_time_utc: nil)
      service.call(votes: [
        {
          legislator_external_id: "VOTER_1",
          vote_value: "yea",
          voted_on: nil
        }
      ])
    end

    it "records coverage with status fetch_failed and re-raises on unhandled processing exception" do
      allow(service).to receive(:upsert_legislator_vote).and_raise(RuntimeError, "DB write failed")

      expect(@coverage_class).to receive(:record_coverage!).with(
        bill: bill,
        chamber: bill.chamber,
        roll_call_number: anything,
        eligible_count: 1,
        matched_count: 0,
        unresolved_tokens: [],
        status: "fetch_failed"
      )

      expect {
        service.call(votes: [
          {
            legislator_external_id: "VOTER_1",
            vote_value: "yea",
            voted_on: Date.current
          }
        ])
      }.to raise_error(RuntimeError, "DB write failed")
    end

    it "records unresolved tokens when voters cannot be matched" do
      unmatched_hash = {
        legislator_external_id: "UNMATCHED_XYZ",
        vote_value: "yea",
        voted_on: Date.current
      }

      expect(@coverage_class).to receive(:record_coverage!).with(
        bill: bill,
        chamber: bill.chamber,
        roll_call_number: anything,
        eligible_count: 1,
        matched_count: 0,
        unresolved_tokens: [hash_including(legislator_external_id: "UNMATCHED_XYZ")],
        status: "unresolved"
      )

      service.call(votes: [unmatched_hash])
    end

    it "records partial status with unresolved_tokens when only some voters match" do
      expect(@coverage_class).to receive(:record_coverage!).with(
        bill: bill,
        chamber: bill.chamber,
        roll_call_number: anything,
        eligible_count: 2,
        matched_count: 1,
        unresolved_tokens: [hash_including(legislator_external_id: "MISSING_OFFICIAL_1")],
        status: "partial"
      )

      service.call(votes: [
        {legislator_external_id: "VOTER_1", vote_value: "yea", voted_on: Date.current},
        {legislator_external_id: "MISSING_OFFICIAL_1", vote_value: "nay", voted_on: Date.current}
      ])
    end

    context "when a matched legislator has no term covering the bill" do
      let(:voter_ballot) { {legislator_external_id: "VOTER_1", vote_value: "yea", voted_on: Date.current} }
      let(:former_ballot) { {legislator_external_id: "FORMER_1", vote_value: "nay", voted_on: Date.current} }

      before do
        cycle_start = TermWindow.cycle_start_year(sway_locale, Date.current)
        @former = create(:legislator, district: district, external_id: "FORMER_1")
        create(:legislator_term, legislator: @former, district: district,
          term_start_year: cycle_start - 4, term_end_year: cycle_start - 2)
      end

      it "records partial when some legislators are skipped" do
        expect(@coverage_class).to receive(:record_coverage!).with(
          hash_including(eligible_count: 2, matched_count: 1, unresolved_tokens: [], status: "partial")
        )

        result = service.call(votes: [voter_ballot, former_ballot])

        expect(result.written_count).to eq(1)
        expect(result.unmatched_count).to eq(0)
        expect(LegislatorVote.where(bill: bill, legislator: @former)).not_to exist
      end

      it "records unresolved with nothing matched when every legislator is skipped" do
        expect(@coverage_class).to receive(:record_coverage!).with(
          hash_including(eligible_count: 1, matched_count: 0, unresolved_tokens: [], status: "unresolved")
        )

        result = service.call(votes: [former_ballot])

        expect(result.written_count).to eq(0)
        expect(result.unmatched_count).to eq(0)
      end
    end

    context "when the votes are already stored" do
      let(:ballot) { {legislator_external_id: "VOTER_1", vote_value: "yea", voted_on: Date.current} }

      it "stays complete on a re-fetch that changes nothing" do
        allow(@coverage_class).to receive(:record_coverage!)
        service.call(votes: [ballot])

        expect(@coverage_class).to receive(:record_coverage!).with(
          hash_including(eligible_count: 1, matched_count: 1, status: "complete")
        )

        service.call(votes: [ballot])
      end

      it "counts an admin's manual vote as covered without counting it as written" do
        create(:legislator_vote, :against, bill: bill, legislator: voter, legislator_term: @voter_term, source: "manual")

        expect(@coverage_class).to receive(:record_coverage!).with(
          hash_including(eligible_count: 1, matched_count: 1, status: "complete")
        )

        result = service.call(votes: [ballot])

        expect(result.written_count).to eq(0)
        expect(LegislatorVote.find_by(bill: bill, legislator: voter).support).to eq(LegislatorVote::Support::AGAINST)
      end
    end

    it "records unresolved when a write fails" do
      allow(LegislatorVote).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new("duplicate"))

      expect(@coverage_class).to receive(:record_coverage!).with(
        hash_including(eligible_count: 1, matched_count: 0, status: "unresolved")
      )

      service.call(votes: [{legislator_external_id: "VOTER_1", vote_value: "yea", voted_on: Date.current}])
    end

    it "records unresolved when no row names a voter" do
      expect(@coverage_class).to receive(:record_coverage!).with(
        hash_including(eligible_count: 1, matched_count: 0, status: "unresolved")
      )

      service.call(votes: [{vote_value: "yea", voted_on: Date.current}])
    end

    it "derives roll_call_number with priority roll_call_number -> house -> senate -> external_id -> '1'" do
      single_vote = [{legislator_external_id: "VOTER_1", vote_value: "yea", voted_on: Date.current}]

      allow(bill).to receive(:vote).and_return(double("Vote", roll_call_number: "RC-99", house_roll_call_vote_number: 101, senate_roll_call_vote_number: 202))
      expect(@coverage_class).to receive(:record_coverage!).with(hash_including(roll_call_number: "RC-99"))
      service.call(votes: single_vote)

      allow(bill).to receive(:vote).and_return(double("Vote", house_roll_call_vote_number: 101, senate_roll_call_vote_number: 202))
      expect(@coverage_class).to receive(:record_coverage!).with(hash_including(roll_call_number: "101"))
      service.call(votes: single_vote)

      allow(bill).to receive(:vote).and_return(double("Vote", house_roll_call_vote_number: nil, senate_roll_call_vote_number: 202))
      expect(@coverage_class).to receive(:record_coverage!).with(hash_including(roll_call_number: "202"))
      service.call(votes: single_vote)

      allow(bill).to receive(:vote).and_return(nil)
      bill.external_id = "BILL-EXT-777"
      expect(@coverage_class).to receive(:record_coverage!).with(hash_including(roll_call_number: "BILL-EXT-777"))
      service.call(votes: single_vote)

      bill.external_id = ""
      expect(@coverage_class).to receive(:record_coverage!).with(hash_including(roll_call_number: "1"))
      service.call(votes: single_vote)
    end
  end

  describe "Open Legislator native integration (OL-34d.11.7)" do
    let(:real_open_leg_client) do
      OpenLegislator::Client.new(base_url: "https://api.open-legislator.test/api/v1")
    end
    let(:legistar_mock_client) { instance_double(Legistar::Client) }

    def fixture_content(name)
      Rails.root.join("spec", "fixtures", "open_legislator", name).read
    end

    before do
      bill.update!(external_id: "24-0001", house_vote_date_time_utc: nil)
      service.open_legislator_client = real_open_leg_client
      service.legistar_client = legistar_mock_client
    end

    context "with explicit source: :open_legislator" do
      it "recognizes open_legislator source and enables final passage check" do
        custom_service = described_class.new(bill, source: :open_legislator)
        expect(custom_service.source).to eq(:open_legislator)
        expect(custom_service.send(:open_legislator_source?)).to be true
        expect(custom_service.send(:should_apply_final_passage?)).to be true
      end

      it "updates house_vote_date_time_utc when Open Legislator matter has passing action" do
        stub_request(:get, "https://api.open-legislator.test/api/v1/matters")
          .with(query: hash_including("file_number" => "24-0001"))
          .to_return(
            status: 200,
            body: fixture_content("matters_index_by_file_number.json"),
            headers: {"Content-Type" => "application/json"}
          )

        stub_request(:get, "https://api.open-legislator.test/api/v1/matters/ordinance-24-0001-housing-affordability")
          .to_return(
            status: 200,
            body: fixture_content("matter_show_passed.json"),
            headers: {"Content-Type" => "application/json"}
          )

        service.call(votes: [], infer_sponsors_if_empty: false, source: :open_legislator)

        expect(bill.reload.house_vote_date_time_utc).to eq(Time.zone.parse("2026-05-15"))
      end

      it "updates house_vote_date_time_utc when matter has enacted outcome" do
        stub_request(:get, "https://api.open-legislator.test/api/v1/matters")
          .with(query: hash_including("file_number" => "24-0001"))
          .to_return(
            status: 200,
            body: fixture_content("matters_index_by_file_number.json"),
            headers: {"Content-Type" => "application/json"}
          )

        stub_request(:get, "https://api.open-legislator.test/api/v1/matters/ordinance-24-0001-housing-affordability")
          .to_return(
            status: 200,
            body: fixture_content("matter_show_enacted_without_actions.json"),
            headers: {"Content-Type" => "application/json"}
          )

        service.call(votes: [], infer_sponsors_if_empty: false, source: :open_legislator)

        expect(bill.reload.house_vote_date_time_utc).to eq(Time.zone.parse("2026-06-01"))
      end

      it "honestly preserves nil vote date and manufactures zero votes when outcome is missing" do
        stub_request(:get, "https://api.open-legislator.test/api/v1/matters")
          .with(query: hash_including("file_number" => "24-0001"))
          .to_return(
            status: 200,
            body: fixture_content("matters_index_by_file_number.json"),
            headers: {"Content-Type" => "application/json"}
          )

        stub_request(:get, "https://api.open-legislator.test/api/v1/matters/ordinance-24-0001-housing-affordability")
          .to_return(
            status: 200,
            body: fixture_content("matter_show_missing_outcome.json"),
            headers: {"Content-Type" => "application/json"}
          )

        expect(SwayLogging).to receive(:info).with(
          /matter found in Open Legislator .* but has no passing action or enacted outcome — honest no-op/
        )
        expect(legistar_mock_client).not_to receive(:matters)

        service.call(votes: [], infer_sponsors_if_empty: false, source: :open_legislator)

        expect(bill.reload.house_vote_date_time_utc).to be_nil
        expect(LegislatorVote.where(bill: bill).count).to eq(0)
      end

      it "falls back safely to legistar_client when Open Legislator returns nil (not found)" do
        stub_request(:get, "https://api.open-legislator.test/api/v1/matters")
          .with(query: hash_including("file_number" => "24-0001"))
          .to_return(
            status: 200,
            body: fixture_content("matters_index_empty.json"),
            headers: {"Content-Type" => "application/json"}
          )

        rules = instance_double(
          SwayLocale::JurisdictionRules,
          final_passage_action_ids: [42]
        )
        allow(sway_locale).to receive(:jurisdiction_rules).and_return(rules)

        expect(SwayLogging).to receive(:warn).with(
          /Open Legislator matter not found for bill_id=#{bill.id} external_id=24-0001 — falling back to Legistar/
        )

        expect(legistar_mock_client).to receive(:matters).with(filter: "MatterFile eq '24-0001'").and_return([
          {"MatterId" => 777}
        ])
        expect(legistar_mock_client).to receive(:matter_histories).with(777).and_return([
          {
            "MatterHistoryActionId" => 42,
            "MatterHistoryActionDate" => "2026-07-20T00:00:00Z",
            "MatterHistoryId" => 900
          }
        ])

        service.call(votes: [], infer_sponsors_if_empty: false, source: :open_legislator)

        expect(bill.reload.house_vote_date_time_utc).to eq(Time.zone.parse("2026-07-20T00:00:00Z"))
      end

      it "falls back safely to legistar_client when Open Legislator raises an HttpError" do
        stub_request(:get, "https://api.open-legislator.test/api/v1/matters")
          .with(query: hash_including("file_number" => "24-0001"))
          .to_return(
            status: 503,
            body: '{"error":"service_unavailable"}',
            headers: {"Content-Type" => "application/json"}
          )

        rules = instance_double(
          SwayLocale::JurisdictionRules,
          final_passage_action_ids: [42]
        )
        allow(sway_locale).to receive(:jurisdiction_rules).and_return(rules)

        expect(SwayLogging).to receive(:warn).with(
          /Open Legislator lookup error for bill_id=#{bill.id} external_id=24-0001: .* — falling back to Legistar/
        )

        expect(legistar_mock_client).to receive(:matters).with(filter: "MatterFile eq '24-0001'").and_return([
          {"MatterId" => 888}
        ])
        expect(legistar_mock_client).to receive(:matter_histories).with(888).and_return([
          {
            "MatterHistoryActionId" => 42,
            "MatterHistoryActionDate" => "2026-08-10T00:00:00Z",
            "MatterHistoryId" => 901
          }
        ])

        service.call(votes: [], infer_sponsors_if_empty: false, source: :open_legislator)

        expect(bill.reload.house_vote_date_time_utc).to eq(Time.zone.parse("2026-08-10T00:00:00Z"))
      end
    end

    describe "fixture schema invariants (OL-34d.11.7)" do
      it "conforms strictly to Open Legislator page envelope, outcome enums, action results, and includes meetings fixtures" do
        verify_open_legislator_fixture_invariants!
      end
    end
  end
end
