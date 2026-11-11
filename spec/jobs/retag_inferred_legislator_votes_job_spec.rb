# frozen_string_literal: true

require "rails_helper"

# @lat: [[retag-inferred-legislator-votes-cleanup#Why it exists]]
RSpec.describe RetagInferredLegislatorVotesJob do
  include ActiveSupport::Testing::TimeHelpers

  it "is configured for the :background queue" do
    expect(described_class.queue_name).to eq("background")
  end

  describe "#perform" do
    let(:sway_locale) { create(:sway_locale) }
    let(:district) { create(:district, sway_locale: sway_locale) }
    let(:legislator) { create(:legislator, district: district) }
    let(:bill) { create(:bill, sway_locale: sway_locale) }

    context "Baltimore (source: legistar)" do
      it "retags every inferred: false legistar row (0/200 real Baltimore roll-calls exist upstream)" do
        row = create(:legislator_vote, bill: bill, legislator: legislator,
          source: "legistar", support: "FOR", inferred: false)

        described_class.new.perform

        expect(row.reload.inferred).to be(true)
      end

      it "does not enqueue a recompute for legistar retags (Baltimore local_signals never queries votes)" do
        create(:legislator_vote, bill: bill, legislator: legislator,
          source: "legistar", support: "FOR", inferred: false)

        expect {
          described_class.new.perform
        }.not_to have_enqueued_job(RecomputeBillInterestingScoreJob)
      end
    end

    context "Congress/Maryland (source: congress/open_states)" do
      # @lat: [[boot-time-backfills#Why the Congress and Maryland recompute is delayed 30 seconds]]
      it "retags an inferred: false FOR row on a bill with NO roll-call pointer and enqueues a delayed recompute" do
        row = create(:legislator_vote, bill: bill, legislator: legislator,
          source: "congress", support: "FOR", inferred: false)

        freeze_time do
          expect {
            described_class.new.perform
          }.to have_enqueued_job(RecomputeBillInterestingScoreJob)
            .with(bill.id).at(30.seconds.from_now)
        end

        expect(row.reload.inferred).to be(true)
      end

      it "leaves rows on bills WITH a roll-call pointer untouched (a real scrape could have produced them)" do
        create(:roll_call, bill: bill, house_roll_call_vote_number: 142, senate_roll_call_vote_number: nil)
        row = create(:legislator_vote, bill: bill, legislator: legislator,
          source: "open_states", support: "FOR", inferred: false)

        expect {
          described_class.new.perform
        }.not_to have_enqueued_job(RecomputeBillInterestingScoreJob)

        expect(row.reload.inferred).to be(false)
      end

      it "leaves non-FOR rows untouched (sponsor inference only ever wrote FOR)" do
        row = create(:legislator_vote, bill: bill, legislator: legislator,
          source: "congress", support: "AGAINST", inferred: false)

        described_class.new.perform

        expect(row.reload.inferred).to be(false)
      end
    end

    it "never touches manual rows" do
      row = create(:legislator_vote, bill: bill, legislator: legislator,
        source: "manual", support: "FOR", inferred: false)

      described_class.new.perform

      expect(row.reload.inferred).to be(false)
    end

    it "is idempotent — a second run matches zero rows and enqueues nothing" do
      create(:legislator_vote, bill: bill, legislator: legislator,
        source: "congress", support: "FOR", inferred: false)

      described_class.new.perform

      expect {
        described_class.new.perform
      }.not_to have_enqueued_job(RecomputeBillInterestingScoreJob)
    end
  end
end
