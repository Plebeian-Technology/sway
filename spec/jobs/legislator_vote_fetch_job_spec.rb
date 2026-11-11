# frozen_string_literal: true

require "rails_helper"

# @lat: [[jurisdiction-rules#Declared executives]]
RSpec.describe LegislatorVoteFetchJob do
  describe "class macros" do
    it "is configured for the :background queue" do
      expect(described_class.queue_name).to eq("background")
    end

    it "uses :polynomially_longer retry (NOT :exponentially_longer)" do
      source = Rails.root.join("app", "jobs", "legislator_vote_fetch_job.rb").read
      expect(source).to include(":polynomially_longer")
      expect(source).not_to include(":exponentially_longer")
    end

    it "re-enqueues (retries) on Legistar::Client::Error rather than discarding" do
      bill = create(:bill)
      allow(Bill).to receive(:find_by).and_return(bill)
      allow(bill.sway_locale).to receive(:jurisdiction_rules)
        .and_return(SwayLocale::JurisdictionRulesRegistry.fetch("baltimore-maryland-united_states"))
      adapter = instance_double(Legislation::Adapters::GenericVoteAdapter)
      allow(Legislation::Adapters::GenericVoteAdapter).to receive(:new).and_return(adapter)
      allow(adapter).to receive(:fetch_votes).and_raise(Legistar::Client::Error.new("503"))

      expect { described_class.perform_now(bill.id) }
        .to have_enqueued_job(described_class).with(bill.id)
    end

    it "has limits_concurrency with on_conflict: :discard" do
      source = Rails.root.join("app", "jobs", "legislator_vote_fetch_job.rb").read
      expect(source).to include("limits_concurrency")
      expect(source).to include("on_conflict: :discard")
      expect(source).to match(/key:\s*->\(bill_id/)
    end
  end

  describe "#perform" do
    let(:bill) { create(:bill, sway_locale: create(:sway_locale, :baltimore)) }

    context "when bill is not found" do
      it "returns nil and does not call any adapter or service" do
        expect(Legislation::Adapters::GenericVoteAdapter).not_to receive(:new)
        expect(GenericLegislatorVoteUpdateService).not_to receive(:new)
        expect { described_class.new.perform(-1) }.not_to raise_error
      end
    end

    context "when bill is found" do
      before do
        allow(Bill).to receive(:find_by).with(id: bill.id).and_return(bill)
      end

      it "fetches votes via GenericVoteAdapter and persists with GenericLegislatorVoteUpdateService" do
        adapter = instance_double(Legislation::Adapters::GenericVoteAdapter)
        update_service = instance_double(GenericLegislatorVoteUpdateService)
        votes = [{legislator_external_id: "L1", vote_value: "yea", voted_on: Date.current}]

        expect(Legislation::Adapters::GenericVoteAdapter).to receive(:new)
          .with(bill.sway_locale.jurisdiction_rules.vote_rules || {})
          .and_return(adapter)
        expect(adapter).to receive(:fetch_votes).with(bill).and_return(votes)
        expect(GenericLegislatorVoteUpdateService).to receive(:new).and_return(update_service)
        expect(update_service).to receive(:call).with(bill: bill, votes: votes)

        described_class.new.perform(bill.id)
      end

      it "accepts force_refresh keyword argument cleanly" do
        adapter = instance_double(Legislation::Adapters::GenericVoteAdapter)
        update_service = instance_double(GenericLegislatorVoteUpdateService)
        allow(Legislation::Adapters::GenericVoteAdapter).to receive(:new).and_return(adapter)
        allow(adapter).to receive(:fetch_votes).and_return([])
        allow(GenericLegislatorVoteUpdateService).to receive(:new).and_return(update_service)
        allow(update_service).to receive(:call)

        expect { described_class.new.perform(bill.id, force_refresh: true) }.not_to raise_error
      end
    end

    context "when the bill's locale has no declaration" do
      it "refuses instead of handing the bill to a jurisdiction that did not publish it" do
        undeclared = create(:sway_locale, city: "austin", state: "TX", country: "United States")
        austin_bill = create(:bill, sway_locale: undeclared)

        expect(GenericLegislatorVoteUpdateService).not_to receive(:new)
        expect { described_class.run_service_for(austin_bill.id) }
          .to raise_error(SwayLocale::JurisdictionRules::Undeclared, /austin/)
      end
    end

    context "when the bill is a Congress bill" do
      before do
        @congress_locale = create(:sway_locale, :congress)
        @senate_district = create(:district, sway_locale: @congress_locale, name: "MD0")
        @house_district = create(:district, sway_locale: @congress_locale, name: "MD7")
        @senator = create(
          :legislator,
          district: @senate_district,
          title: "Sen.",
          external_id: "S000001",
          first_name: "Chris",
          last_name: "Van Hollen",
          party: "D"
        ).tap do |leg|
          @senate_term = create(:legislator_term, :prior_term, legislator: leg, district: @senate_district, title: "Sen.")
        end
        @representative = create(
          :legislator,
          district: @house_district,
          title: "Rep.",
          external_id: "H000001",
          first_name: "Kweisi",
          last_name: "Mfume",
          party: "D"
        ).tap do |leg|
          @house_term = create(:legislator_term, :prior_term, legislator: leg, district: @house_district, title: "Rep.")
        end
        @congress_bill = create(
          :bill,
          sway_locale: @congress_locale,
          legislator: @representative,
          external_id: "hr1234",
          senate_vote_date_time_utc: Time.utc(2024, 6, 18),
          house_vote_date_time_utc: Time.utc(2024, 6, 18)
        )
        @vote_record = create(
          :vote,
          bill: @congress_bill,
          senate_roll_call_vote_number: "200",
          house_roll_call_vote_number: "150"
        )
        @senate_vote_double = Scraper::LegislatorVote.new(
          external_id: @senator.external_id,
          support: "FOR",
          first_name: @senator.first_name,
          last_name: @senator.last_name,
          party: @senator.party.to_s,
          state_code: "MD"
        )
        @house_vote_double = Scraper::LegislatorVote.new(
          external_id: @representative.external_id,
          support: "FOR",
          first_name: @representative.first_name,
          last_name: @representative.last_name,
          party: @representative.party.to_s,
          state_code: "MD"
        )

        @senate_scraper = instance_double(Scraper::Congress::Senate::LegislatorVotes)
        allow(Scraper::Congress::Senate::LegislatorVotes).to receive(:new).and_return(@senate_scraper)
        allow(@senate_scraper).to receive(:process).and_return([@senate_vote_double])
        allow(@senate_scraper).to receive(:identity).and_return(
          instance_double(
            Scraper::Congress::RollCallIdentity,
            taken_on?: true,
            names?: true,
            document_name: "hr1234",
            question: "On Passage of the Bill",
            title: nil,
            voted_on: Date.new(2024, 6, 18),
            to_h: {}
          )
        )

        @house_scraper = instance_double(Scraper::Congress::House::LegislatorVotes)
        allow(Scraper::Congress::House::LegislatorVotes).to receive(:new).and_return(@house_scraper)
        allow(@house_scraper).to receive(:process).and_return([@house_vote_double])
        allow(@house_scraper).to receive(:identity).and_return(
          instance_double(
            Scraper::Congress::RollCallIdentity,
            taken_on?: true,
            names?: true,
            document_name: "hr1234",
            question: "On Passage of the Bill",
            title: nil,
            voted_on: Date.new(2024, 6, 18),
            to_h: {}
          )
        )
        LegislatorVote.where(bill: @congress_bill).delete_all
      end

      it "raises Scraper::Congress::RollCallMismatch and writes zero votes when roll call date mismatches" do
        mismatched_identity = instance_double(
          Scraper::Congress::RollCallIdentity,
          taken_on?: false,
          names?: true,
          document_name: "hr1234",
          question: "On Passage of the Bill",
          title: nil,
          voted_on: Date.new(2026, 1, 1),
          to_h: {}
        )
        allow(@senate_scraper).to receive(:identity).and_return(mismatched_identity)
        allow(@house_scraper).to receive(:identity).and_return(mismatched_identity)

        expect { described_class.run_service_for(@congress_bill.id) }
          .to raise_error(Scraper::Congress::RollCallMismatch)
        expect(LegislatorVote.where(bill: @congress_bill)).not_to exist
      end

      it "persists votes for the healthy chamber, suppresses sponsor inference, and re-raises when one chamber raises RollCallUnavailable" do
        unavailable_err = Scraper::Congress::RollCallUnavailable.new(
          chamber: :senate,
          congress: 118,
          session: 2,
          roll_call_number: 200,
          reason: "Senate upstream unavailable"
        )
        allow(@senate_scraper).to receive(:process).and_raise(unavailable_err)

        expect { described_class.run_service_for(@congress_bill.id) }
          .to raise_error(Scraper::Congress::RollCallUnavailable)

        expect(LegislatorVote.where(bill: @congress_bill, legislator: @representative)).to exist
        expect(LegislatorVote.where(bill: @congress_bill, legislator: @senator)).not_to exist
        expect(LegislatorVote.where(bill: @congress_bill, inferred: true)).not_to exist
      end

      it "records LegislativeVoteCoverage per chamber, writes votes with source: 'congress', and enqueues score recompute jobs on successful fetch" do
        coverage_double = class_double("LegislativeVoteCoverage")
        stub_const("LegislativeVoteCoverage", coverage_double)
        stub_const(
          "LegislativeVoteCoverage::Status",
          Module.new do
            const_set(:COMPLETE, "complete")
            const_set(:PARTIAL, "partial")
            const_set(:UNRESOLVED, "unresolved")
            const_set(:MISSING_VOTE_DATE, "missing_vote_date")
            const_set(:FETCH_FAILED, "fetch_failed")
          end
        )

        expect(coverage_double).to receive(:record_coverage!).with(
          bill: @congress_bill,
          chamber: "senate",
          roll_call_number: "200",
          eligible_count: 1,
          matched_count: 1,
          unresolved_tokens: [],
          status: "complete"
        )

        expect(coverage_double).to receive(:record_coverage!).with(
          bill: @congress_bill,
          chamber: "house",
          roll_call_number: "150",
          eligible_count: 1,
          matched_count: 1,
          unresolved_tokens: [],
          status: "complete"
        )

        expect {
          described_class.run_service_for(@congress_bill.id)
        }.to have_enqueued_job(OnLegislatorVoteUpdateScoresJob).with(@senator.id, @senate_term.id)
          .and have_enqueued_job(OnLegislatorVoteUpdateScoresJob).with(@representative.id, @house_term.id)
          .and have_enqueued_job(RecomputeBillInterestingScoreJob).with(@congress_bill.id).twice

        votes = LegislatorVote.where(bill: @congress_bill)
        expect(votes.count).to eq(2)
        expect(votes.pluck(:source).uniq).to eq(["congress"])
        expect(votes.pluck(:inferred).uniq).to eq([false])
      end
    end
  end

  describe "Congress roll-call retry and error propagation" do
    include ActiveJob::TestHelper
    include ActiveSupport::Testing::TimeHelpers

    let(:bill) { create(:bill, sway_locale: create(:sway_locale, :congress)) }

    before do
      bill
      clear_enqueued_jobs
    end

    it "enqueues a retry about 1 hour out when perform_now encounters RollCallUnavailable" do
      err = Scraper::Congress::RollCallUnavailable.new(
        chamber: :senate,
        congress: 118,
        session: 2,
        roll_call_number: 200,
        reason: "Senate upstream unavailable"
      )
      allow(CongressLegislatorVoteUpdateService).to receive(:call).with(bill).and_raise(err)

      freeze_time do
        expect {
          described_class.perform_now(bill.id)
        }.to have_enqueued_job(described_class).with(bill.id)

        expect(enqueued_jobs.size).to eq(1)
        retry_job = enqueued_jobs.last
        expect(retry_job[:job]).to eq(described_class)
        expect(retry_job[:args]).to eq([bill.id])
        scheduled_at = Time.zone.at(retry_job[:at])
        expect(scheduled_at).to be_within(15.minutes).of(1.hour.from_now)
      end
    end

    it "enqueues retries on attempts 1 and 2 (1 hour apart) and re-raises RollCallUnavailable on attempt 3 with no 4th retry" do
      err = Scraper::Congress::RollCallUnavailable.new(
        chamber: :senate,
        congress: 118,
        session: 2,
        roll_call_number: 200,
        reason: "Senate upstream unavailable"
      )
      allow(CongressLegislatorVoteUpdateService).to receive(:call).with(bill).and_raise(err)

      freeze_time do
        job = described_class.new(bill.id)

        expect { job.perform_now }.not_to raise_error
        expect(enqueued_jobs.size).to eq(1)
        first_retry_at = Time.zone.at(enqueued_jobs.last[:at])
        expect(first_retry_at).to be_within(15.minutes).of(1.hour.from_now)

        travel 1.hour

        expect { job.perform_now }.not_to raise_error
        expect(enqueued_jobs.size).to eq(2)
        second_retry_at = Time.zone.at(enqueued_jobs.last[:at])
        expect(second_retry_at).to be_within(15.minutes).of(1.hour.from_now)
        expect(second_retry_at - first_retry_at).to be_within(15.minutes).of(1.hour)

        travel 1.hour

        expect { job.perform_now }.to raise_error(Scraper::Congress::RollCallUnavailable)
        expect(enqueued_jobs.size).to eq(2)
      end
    end

    it "propagates Scraper::Congress::RollCallMismatch out of perform_now and enqueues no retry" do
      err = Scraper::Congress::RollCallMismatch.new("Roll call date does not match")
      allow(CongressLegislatorVoteUpdateService).to receive(:call).with(bill).and_raise(err)

      expect {
        described_class.perform_now(bill.id)
      }.to raise_error(Scraper::Congress::RollCallMismatch)
      expect(enqueued_jobs).to be_empty
    end

    it "propagates Scraper::Congress::RollCallNotOnTheBill out of perform_now and enqueues no retry" do
      err = Scraper::Congress::RollCallNotOnTheBill.new("Roll call not on the bill")
      allow(CongressLegislatorVoteUpdateService).to receive(:call).with(bill).and_raise(err)

      expect {
        described_class.perform_now(bill.id)
      }.to raise_error(Scraper::Congress::RollCallNotOnTheBill)
      expect(enqueued_jobs).to be_empty
    end
  end
end
