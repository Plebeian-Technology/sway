# frozen_string_literal: true

require "rails_helper"
require "rake"

# @lat: [[legislator-votes-update-rake-task#Why run_service_for, not perform_now]]
RSpec.describe "sway:legislator_votes:update" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:legislator_votes:update")
  end

  before do
    Rake::Task["sway:legislator_votes:update"].reenable
    allow(LegislatorVoteFetchJob).to receive(:run_service_for)
  end

  describe "no locale arg (GLOBAL — Bill.all)" do
    it "iterates every Bill across every SwayLocale" do
      locale_a = create(:sway_locale, city: "maryland", state: "maryland",
        country: "united_states")
      locale_b = create(:sway_locale, city: "baltimore", state: "maryland",
        country: "united_states")
      bill1 = create(:bill, sway_locale: locale_a)
      bill2 = create(:bill, sway_locale: locale_b)

      Rake::Task["sway:legislator_votes:update"].invoke

      expect(LegislatorVoteFetchJob).to have_received(:run_service_for).with(bill1.id)
      expect(LegislatorVoteFetchJob).to have_received(:run_service_for).with(bill2.id)
    end
  end

  describe "with locale arg (HIGH-1: canonical 'city-state-country' name)" do
    it "matches via SwayLocale.find_by_name_parts and scopes to that locale's bills" do
      other_locale = create(:sway_locale, city: "maryland", state: "maryland",
        country: "united_states")
      baltimore = create(:sway_locale, city: "baltimore", state: "maryland",
        country: "united_states")
      other_bill = create(:bill, sway_locale: other_locale)
      baltimore_bill = create(:bill, sway_locale: baltimore)

      Rake::Task["sway:legislator_votes:update"].invoke("baltimore-maryland-united_states")

      expect(LegislatorVoteFetchJob).to have_received(:run_service_for).with(baltimore_bill.id)
      expect(LegislatorVoteFetchJob).not_to have_received(:run_service_for).with(other_bill.id)
    end

    it "aborts when locale arg matches nothing" do
      expect {
        Rake::Task["sway:legislator_votes:update"].invoke("atlantis-atlantis-atlantis")
      }.to raise_error(SystemExit)
    end
  end

  describe "circuit breaker" do
    # @lat: [[legislator-votes-update-rake-task#Circuit breaker and permanent refusals]]
    it "aborts after 3 consecutive bill errors (Legistar::Client::Error reaches the breaker)" do
      sway_locale = create(:sway_locale, city: "baltimore", state: "maryland",
        country: "united_states")
      5.times do |i|
        create(:bill, sway_locale: sway_locale,
          scheduled_release_date_utc: (Time.zone.now - (i + 2).days).to_date)
      end
      allow(LegislatorVoteFetchJob).to receive(:run_service_for)
        .and_raise(Legistar::Client::Error.new("upstream 503"))

      expect {
        Rake::Task["sway:legislator_votes:update"].invoke
      }.to raise_error(SystemExit) # the task exits with status 1 because of the errors

      expect(LegislatorVoteFetchJob).to have_received(:run_service_for).exactly(3).times
    end

    it "resets the consecutive counter on a successful bill" do
      sway_locale = create(:sway_locale, city: "baltimore", state: "maryland",
        country: "united_states")
      5.times do |i|
        create(:bill, sway_locale: sway_locale,
          scheduled_release_date_utc: (Time.zone.now - (i + 2).days).to_date)
      end
      call_count = 0
      allow(LegislatorVoteFetchJob).to receive(:run_service_for) do
        call_count += 1
        raise Legistar::Client::Error.new("blip") if call_count.odd?
      end

      expect {
        Rake::Task["sway:legislator_votes:update"].invoke
      }.to raise_error(SystemExit)
      expect(LegislatorVoteFetchJob).to have_received(:run_service_for).exactly(5).times
    end
  end

  describe "permanent per-bill refusals" do
    # @lat: [[legislator-votes-update-rake-task#Circuit breaker and permanent refusals]]
    it "does not trip breaker on 4 consecutive permanent refusals and updates the 5th bill" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      bills = Array.new(5) do |i|
        create(:bill, sway_locale: sway_locale,
          scheduled_release_date_utc: (Time.zone.now - (i + 2).days).to_date)
      end

      call_count = 0
      allow(LegislatorVoteFetchJob).to receive(:run_service_for) do |_bill_id|
        call_count += 1
        if call_count <= 4
          raise Scraper::Congress::RollCallNotOnTheBill.new("senate roll call asked cloture")
        end
      end

      expect {
        Rake::Task["sway:legislator_votes:update"].invoke
      }.not_to raise_error

      expect(LegislatorVoteFetchJob).to have_received(:run_service_for).exactly(5).times
      expect(LegislatorVoteFetchJob).to have_received(:run_service_for).with(bills.last.id)
    end

    it "aborts after 3 consecutive transport errors and exits 1" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      5.times do |i|
        create(:bill, sway_locale: sway_locale,
          scheduled_release_date_utc: (Time.zone.now - (i + 2).days).to_date)
      end
      allow(LegislatorVoteFetchJob).to receive(:run_service_for)
        .and_raise(Faraday::ConnectionFailed.new("upstream network down"))

      expect {
        Rake::Task["sway:legislator_votes:update"].invoke
      }.to raise_error(SystemExit) { |error|
        expect(error.status).to eq(1)
      }

      expect(LegislatorVoteFetchJob).to have_received(:run_service_for).exactly(3).times
    end

    it "exits 0 when only permanent per-bill refusals occur" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      3.times do |i|
        create(:bill, sway_locale: sway_locale,
          scheduled_release_date_utc: (Time.zone.now - (i + 2).days).to_date)
      end
      allow(LegislatorVoteFetchJob).to receive(:run_service_for)
        .and_raise(Scraper::Congress::RollCallNotOnTheBill.new("roll call not on the bill"))

      expect {
        Rake::Task["sway:legislator_votes:update"].invoke
      }.not_to raise_error

      expect(LegislatorVoteFetchJob).to have_received(:run_service_for).exactly(3).times
    end

    it "exits 1 when transport errors occur even without tripping the breaker" do
      sway_locale = create(:sway_locale, city: "baltimore", state: "maryland",
        country: "united_states")
      2.times do |i|
        create(:bill, sway_locale: sway_locale,
          scheduled_release_date_utc: (Time.zone.now - (i + 2).days).to_date)
      end
      call_count = 0
      allow(LegislatorVoteFetchJob).to receive(:run_service_for) do
        call_count += 1
        raise Faraday::ConnectionFailed.new("flaky connection") if call_count == 1
      end

      expect {
        Rake::Task["sway:legislator_votes:update"].invoke
      }.to raise_error(SystemExit) { |error|
        expect(error.status).to eq(1)
      }

      expect(LegislatorVoteFetchJob).to have_received(:run_service_for).exactly(2).times
    end

    it "treats Scraper::Congress::RollCallMismatch as a permanent refusal without tripping the breaker" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      4.times do |i|
        create(:bill, sway_locale: sway_locale,
          scheduled_release_date_utc: (Time.zone.now - (i + 2).days).to_date)
      end
      call_count = 0
      allow(LegislatorVoteFetchJob).to receive(:run_service_for) do
        call_count += 1
        raise Scraper::Congress::RollCallMismatch.new("date mismatch on roll call") if call_count <= 3
      end

      expect {
        Rake::Task["sway:legislator_votes:update"].invoke
      }.not_to raise_error

      expect(LegislatorVoteFetchJob).to have_received(:run_service_for).exactly(4).times
    end

    it "aborts after 3 consecutive RollCallUnavailable errors without counting them as skipped" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      5.times do |i|
        create(:bill, sway_locale: sway_locale,
          scheduled_release_date_utc: (Time.zone.now - (i + 2).days).to_date)
      end
      error = Scraper::Congress::RollCallUnavailable.new(
        chamber: :house,
        congress: 119,
        session: 2,
        roll_call_number: 74,
        reason: "http_404"
      )
      allow(LegislatorVoteFetchJob).to receive(:run_service_for).and_raise(error)
      allow(SwayLogging).to receive(:error).and_call_original
      allow(SwayLogging).to receive(:warn).and_call_original

      expect {
        Rake::Task["sway:legislator_votes:update"].invoke
      }.to raise_error(SystemExit) { |e|
        expect(e.status).to eq(1)
      }

      expect(LegislatorVoteFetchJob).to have_received(:run_service_for).exactly(3).times
      expect(SwayLogging).to have_received(:error).with("legislator_votes:update — 3 consecutive errors, aborting")
      expect(SwayLogging).not_to have_received(:warn).with(/skipped/)
    end

    it "does not reset consecutive error counter on permanent refusal" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      5.times do |i|
        create(:bill, sway_locale: sway_locale,
          scheduled_release_date_utc: (Time.zone.now - (i + 2).days).to_date)
      end
      call_count = 0
      allow(LegislatorVoteFetchJob).to receive(:run_service_for) do
        call_count += 1
        case call_count
        when 1, 3, 4
          raise Faraday::ConnectionFailed.new("network down")
        when 2
          raise Scraper::Congress::RollCallNotOnTheBill.new("cloture motion")
        end
      end

      expect {
        Rake::Task["sway:legislator_votes:update"].invoke
      }.to raise_error(SystemExit) { |error|
        expect(error.status).to eq(1)
      }

      expect(LegislatorVoteFetchJob).to have_received(:run_service_for).exactly(4).times
    end
  end

  describe "all-success run" do
    it "exits 0 when no errors occur" do
      sway_locale = create(:sway_locale, city: "baltimore", state: "maryland",
        country: "united_states")
      create(:bill, sway_locale: sway_locale)
      expect {
        Rake::Task["sway:legislator_votes:update"].invoke
      }.not_to raise_error
    end
  end

  describe "no FORCE env var" do
    it "does not read FORCE from ENV" do
      source = Rails.root.join("lib", "tasks", "sway_legislator_votes.rake").read
      expect(source).not_to match(/ENV\[.FORCE.\]/)
    end
  end

  describe "rake path bypasses the job's rescue_from surface" do
    it "dispatches via run_service_for, never perform_now (retry_on would swallow errors)" do
      source = Rails.root.join("lib", "tasks", "sway_legislator_votes.rake").read
      expect(source).to include("LegislatorVoteFetchJob.run_service_for(bill.id)")
      expect(source).not_to include("perform_now(")
    end
  end
end
