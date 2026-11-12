# frozen_string_literal: true

require "rails_helper"

RSpec.describe LegislatorVoteSweepJob do
  include ActiveJob::TestHelper

  it "is configured for the :background queue" do
    expect(described_class.queue_name).to eq("background")
  end

  describe "#perform" do
    before { clear_enqueued_jobs }

    # @lat: [[legislator-vote-sweep-tests#Executing the prefilter]]
    it "executes the prefilter query without raising (regression for joins(:vote) bug)" do
      _congress_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      expect { described_class.new.perform }.not_to raise_error
    end

    # The sweep no longer passes force_refresh. The keyword does nothing now that
    # the Python-side disk cache has been deleted; LegislatorVoteFetchJob still
    # accepts it only so jobs queued before a deploy do not raise.
    it "enqueues only bills with the required pointer fields (MEDIUM-5)" do
      congress_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      baltimore_locale = create(:sway_locale, city: "baltimore", state: "maryland",
        country: "united_states")

      # Congress: one bill with a roll-call vote (qualifies), one without (filtered out).
      # Give them different scheduled_release_date_utc values, since (date, sway_locale_id) must be unique.
      qualifying_congress = create(:bill, sway_locale: congress_locale,
        scheduled_release_date_utc: 2.days.ago.to_date)
      create(:vote, bill: qualifying_congress, senate_roll_call_vote_number: 42, house_roll_call_vote_number: nil)
      pre_vote_congress = create(:bill, sway_locale: congress_locale,
        scheduled_release_date_utc: 3.days.ago.to_date)
      # No RollCall → filtered out

      # Baltimore: whether a bill qualifies keys off external_id (the factory default),
      # not external_version — external_version: nil here proves it still qualifies.
      qualifying_baltimore = create(:bill, sway_locale: baltimore_locale,
        external_version: nil, scheduled_release_date_utc: 4.days.ago.to_date)
      blank_pointer_baltimore = create(:bill, sway_locale: baltimore_locale,
        external_version: nil, scheduled_release_date_utc: 5.days.ago.to_date)
      blank_pointer_baltimore.update_column(:external_id, "")

      expect {
        described_class.new.perform
      }.to have_enqueued_job(LegislatorVoteFetchJob)
        .with(qualifying_congress.id).once
        .and have_enqueued_job(LegislatorVoteFetchJob)
        .with(qualifying_baltimore.id).once

      # @lat: [[legislator-vote-sweep-tests#Exact enqueue arguments]]
      expect(LegislatorVoteFetchJob).not_to have_been_enqueued.with(pre_vote_congress.id)
      expect(LegislatorVoteFetchJob).not_to have_been_enqueued.with(blank_pointer_baltimore.id)
    end

    it "does NOT duplicate-enqueue a Congress bill that has multiple RollCall rows (.distinct fix)" do
      congress_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      bill = create(:bill, sway_locale: congress_locale)
      create(:vote, bill: bill, senate_roll_call_vote_number: 1, house_roll_call_vote_number: nil)
      create(:vote, bill: bill, house_roll_call_vote_number: 2, senate_roll_call_vote_number: nil)

      expect {
        described_class.new.perform
      }.to have_enqueued_job(LegislatorVoteFetchJob)
        .with(bill.id).exactly(1).times
    end

    it "is a no-op when there are no bills" do
      expect {
        described_class.new.perform
      }.not_to have_enqueued_job(LegislatorVoteFetchJob)
    end

    it "is a no-op when all bills are pre-vote (lack pointer fields)" do
      baltimore_locale = create(:sway_locale, city: "baltimore", state: "maryland",
        country: "united_states")
      bill = create(:bill, sway_locale: baltimore_locale, external_version: nil)
      bill.update_column(:external_id, "")
      expect {
        described_class.new.perform
      }.not_to have_enqueued_job(LegislatorVoteFetchJob)
    end

    it "skips locales that do not publish votes without raising ArgumentError" do
      annapolis = create(:sway_locale, city: "annapolis", state: "maryland", country: "united_states")
      create(:bill, sway_locale: annapolis)

      expect { described_class.new.perform }.not_to raise_error
    end

    it "sweeps roll call votes for maryland_general_assembly engine" do
      expect(described_class::ROLL_CALL_RETRIEVALS).to include("maryland_general_assembly")

      maryland_locale = create(:sway_locale, :maryland)
      qualifying_md = create(:bill, sway_locale: maryland_locale, scheduled_release_date_utc: 2.days.ago.to_date)
      create(:vote, bill: qualifying_md, senate_roll_call_vote_number: 10, house_roll_call_vote_number: nil)

      expect {
        described_class.new.perform
      }.to have_enqueued_job(LegislatorVoteFetchJob).with(qualifying_md.id).once
    end

    # @lat: [[congress-roll-calls#Roll-call numbering restarts every year]]
    describe "settled bills" do
      # @type self: LegislatorVoteSweepSpecContext
      let(:congress_locale) do
        create(:sway_locale, city: "congress", state: "congress", country: "united_states")
      end
      let(:district) { create(:district, sway_locale: congress_locale) }
      let(:congress_legislator) { create(:legislator, district: district) }
      let(:historical_term) do
        create(:legislator_term, :prior_term, legislator: congress_legislator, district: district)
      end
      let(:current_term) do
        start_year = TermWindow.cycle_start_year(congress_locale, Time.current.beginning_of_year + 40.days)
        create(:legislator_term, legislator: congress_legislator, district: district,
          term_start_year: start_year, term_end_year: start_year + 2)
      end

      def roll_call_bill(release_days_ago:, vote_date:)
        bill = create(:bill, sway_locale: congress_locale,
          scheduled_release_date_utc: release_days_ago.days.ago.to_date,
          senate_vote_date_time_utc: vote_date)
        create(:vote, bill: bill, senate_roll_call_vote_number: 200, house_roll_call_vote_number: nil)
        bill
      end

      it "does not enqueue a bill voted in a past year that already holds a real row" do
        bill = roll_call_bill(release_days_ago: 2, vote_date: Time.utc(2024, 6, 18))
        create(:legislator_vote, bill: bill, legislator: congress_legislator, legislator_term: historical_term, source: "congress", inferred: false)

        expect { described_class.new.perform }.not_to have_enqueued_job(LegislatorVoteFetchJob)
      end

      it "still enqueues a past-year bill whose only rows are sponsor guesses" do
        bill = roll_call_bill(release_days_ago: 3, vote_date: Time.utc(2024, 6, 18))
        create(:legislator_vote, :inferred, bill: bill, legislator: congress_legislator, legislator_term: historical_term, source: "congress")

        expect { described_class.new.perform }
          .to have_enqueued_job(LegislatorVoteFetchJob).with(bill.id).once
      end

      it "still enqueues a past-year bill with no rows at all — how a cleaned bill gets re-fetched" do
        bill = roll_call_bill(release_days_ago: 4, vote_date: Time.utc(2024, 6, 18))

        expect { described_class.new.perform }
          .to have_enqueued_job(LegislatorVoteFetchJob).with(bill.id).once
      end

      it "still enqueues a bill voted THIS year even when rows are recorded, so late corrections arrive" do
        bill = roll_call_bill(release_days_ago: 5, vote_date: Time.current.beginning_of_year + 40.days)
        create(:legislator_vote, bill: bill, legislator: congress_legislator, legislator_term: current_term, source: "congress", inferred: false)

        expect { described_class.new.perform }
          .to have_enqueued_job(LegislatorVoteFetchJob).with(bill.id).once
      end
    end

    # The pacing must have an upper bound, so a sweep over large locales cannot
    # drift past the quiet hours it is meant to run in. The cap is
    # LegislatorVoteSweepJob::WAIT_CEILING_SECONDS, 1800 by default.
    describe "WR-03 bounded pacing" do
      it "exposes a WAIT_CEILING_SECONDS constant" do
        expect(described_class::WAIT_CEILING_SECONDS).to be_a(Integer)
        expect(described_class::WAIT_CEILING_SECONDS).to be > 0
      end

      # @lat: [[legislator-vote-sweep-tests#Bounded pacing]]
      it "paces enqueues at 0.5s offsets and caps the wait at WAIT_CEILING_SECONDS (behavioral)" do
        stub_const("LegislatorVoteSweepJob::WAIT_CEILING_SECONDS", 1)
        congress_locale = create(:sway_locale, city: "congress", state: "congress",
          country: "united_states")
        bills = Array.new(4) do |i|
          # Different dates, because (scheduled_release_date_utc, sway_locale_id) must be unique.
          create(:bill, sway_locale: congress_locale,
            scheduled_release_date_utc: (i + 2).days.ago.to_date)
        end
        bills.each do |bill|
          create(:vote, bill: bill, senate_roll_call_vote_number: 1, house_roll_call_vote_number: nil)
        end

        waits = [] #: Array[untyped]
        configurator = instance_double(ActiveJob::ConfiguredJob, perform_later: nil)
        allow(LegislatorVoteFetchJob).to receive(:set) do |wait:|
          waits << wait
          configurator
        end

        described_class.new.perform

        expect(waits).to all(be_a(ActiveSupport::Duration))
        expect(waits.map(&:to_f)).to eq([0.0, 0.5, 1.0, 1.0])
      end

      it "passes the capped wait to LegislatorVoteFetchJob.set(wait:) as an ActiveSupport::Duration" do
        congress_locale = create(:sway_locale, city: "congress", state: "congress",
          country: "united_states")
        bill = create(:bill, sway_locale: congress_locale)
        create(:vote, bill: bill, senate_roll_call_vote_number: 1, house_roll_call_vote_number: nil)

        configurator = instance_double(ActiveJob::ConfiguredJob)
        # hash_including(:wait) on its own would pass for a plain Float. Pin that
        # the value really is an ActiveSupport::Duration.
        expect(LegislatorVoteFetchJob).to receive(:set)
          .with(hash_including(wait: an_instance_of(ActiveSupport::Duration)))
          .and_return(configurator)
        expect(configurator).to receive(:perform_later).with(bill.id)

        described_class.new.perform
      end
    end
  end

  describe "decoupled retrieval rules" do
    it "defines ROLL_CALL_RETRIEVALS and EXTERNAL_ID_RETRIEVALS" do
      expect(described_class::ROLL_CALL_RETRIEVALS).to include("congress_dot_gov", "generic_csv", "open_states")
      expect(described_class::EXTERNAL_ID_RETRIEVALS).to include("legistar", "generic_rest", "generic_json")
    end

    it "prioritizes rules.retrieval_for(:vote) over vote_rules[:engine]" do
      maryland_locale = create(:sway_locale, :maryland)
      rules = maryland_locale.jurisdiction_rules
      allow(maryland_locale).to receive(:declared_jurisdiction_rules).and_return(rules)
      allow(rules).to receive(:retrieval_for).with(:vote).and_return("maryland_general_assembly")

      qualifying = create(:bill, sway_locale: maryland_locale, scheduled_release_date_utc: 2.days.ago.to_date)
      create(:vote, bill: qualifying, house_roll_call_vote_number: 77, senate_roll_call_vote_number: nil)

      expect {
        described_class.new.perform
      }.to have_enqueued_job(LegislatorVoteFetchJob).with(qualifying.id)
    end

    it "raises ArgumentError on unrecognized vote engines" do
      maryland_locale = create(:sway_locale, :maryland)
      job = described_class.new

      expect {
        job.send(:filter_scope_for_engine, Bill.where(sway_locale: maryland_locale), "bogus_engine", sway_locale: maryland_locale)
      }.to raise_error(
        ArgumentError,
        "LegislatorVoteSweepJob has no bill filter for vote engine \"bogus_engine\" (#{maryland_locale.name})"
      )
    end
  end
end
