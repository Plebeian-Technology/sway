# frozen_string_literal: true

require "rails_helper"

# @lat: [[backfill-bill-interesting-scores-job-design#Why a bad bill does not abort the batch]]
RSpec.describe BackfillBillInterestingScoresJob, type: :job do
  it "is configured for the :background queue" do
    expect(described_class.queue_name).to eq("background")
  end

  describe "#perform" do
    it "creates a score row for every in-scope unscored bill across locales" do
      congress_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      baltimore_locale = create(:sway_locale, city: "baltimore", state: "maryland",
        country: "united_states")

      congress_bill = create(:bill, sway_locale: congress_locale,
        introduced_date_time_utc: 10.days.ago, scheduled_release_date_utc: 1.day.ago)
      baltimore_bill = create(:bill, sway_locale: baltimore_locale,
        introduced_date_time_utc: 10.days.ago, scheduled_release_date_utc: 2.days.ago)

      expect {
        described_class.new.perform
      }.to change(BillInterestingScore, :count).by(2)

      expect(BillInterestingScore.exists?(bill_id: congress_bill.id)).to be true
      expect(BillInterestingScore.exists?(bill_id: baltimore_bill.id)).to be true
    end

    it "is idempotent — a second run scores zero additional bills" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      bill = create(:bill, sway_locale: sway_locale, introduced_date_time_utc: 10.days.ago)

      described_class.new.perform
      expect(BillInterestingScore.where(bill_id: bill.id).count).to eq(1)

      expect {
        described_class.new.perform
      }.not_to change(BillInterestingScore, :count)
    end

    it "skips a bill that already carries a score row while still scoring a sibling unscored bill" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      already_scored = create(:bill, sway_locale: sway_locale,
        introduced_date_time_utc: 10.days.ago, scheduled_release_date_utc: 1.day.ago)
      create(:bill_interesting_score, bill: already_scored)
      unscored = create(:bill, sway_locale: sway_locale,
        introduced_date_time_utc: 10.days.ago, scheduled_release_date_utc: 2.days.ago)

      expect {
        described_class.new.perform
      }.to change(BillInterestingScore, :count).by(1)

      expect(BillInterestingScore.where(bill_id: unscored.id).count).to eq(1)
      expect(BillInterestingScore.where(bill_id: already_scored.id).count).to eq(1)
    end

    it "excludes a bill introduced before its locale's current session" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      prior_session = create(:legislative_session, sway_locale: sway_locale, active: false,
        start_date: 90.days.ago, end_date: 30.days.ago)
      create(:bill, sway_locale: sway_locale, legislative_session: prior_session,
        introduced_date_time_utc: 60.days.ago)

      expect {
        described_class.new.perform
      }.not_to change(BillInterestingScore, :count)
    end

    it "isolates a per-bill calculator failure so the batch continues" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress",
        country: "united_states")
      good_bill = create(:bill, sway_locale: sway_locale,
        introduced_date_time_utc: 10.days.ago, scheduled_release_date_utc: 1.day.ago)
      bad_bill = create(:bill, sway_locale: sway_locale,
        introduced_date_time_utc: 10.days.ago, scheduled_release_date_utc: 2.days.ago)

      allow(BillInterestingScoreCalculator).to receive(:new).and_call_original
      allow(BillInterestingScoreCalculator).to receive(:new).with(bad_bill)
        .and_raise(StandardError, "boom")

      expect {
        described_class.new.perform
      }.to change(BillInterestingScore, :count).by(1)

      expect(BillInterestingScore.exists?(bill_id: good_bill.id)).to be true
      expect(BillInterestingScore.exists?(bill_id: bad_bill.id)).to be false
    end

    it "is a no-op when there are no in-scope bills" do
      expect {
        described_class.new.perform
      }.not_to change(BillInterestingScore, :count)
    end
  end
end
