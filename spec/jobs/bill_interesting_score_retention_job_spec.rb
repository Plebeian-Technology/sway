# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-interesting-score#Why retention keeps the newest row for each bill]]
RSpec.describe BillInterestingScoreRetentionJob, type: :job do
  def create_score(bill, created_at:)
    create(:bill_interesting_score, bill: bill, created_at: created_at, computed_at: created_at)
  end

  let(:bill) { create(:bill) }

  before do
    allow(SwayLogging).to receive(:info)
    BillInterestingScore.delete_all
  end

  describe "#perform" do
    it "keeps the newest row for a bill even when every row is older than the window" do
      oldest = create_score(bill, created_at: 90.days.ago)
      middle = create_score(bill, created_at: 60.days.ago)
      newest = create_score(bill, created_at: 45.days.ago)

      expect { described_class.new.perform }.to change { BillInterestingScore.count }.from(3).to(1)
      expect(BillInterestingScore.pluck(:id)).to eq([newest.id])
      expect(BillInterestingScore.exists?(oldest.id)).to be(false)
      expect(BillInterestingScore.exists?(middle.id)).to be(false)
    end

    it "keeps a superseded row that is younger than the window" do
      recent_superseded = create_score(bill, created_at: 10.days.ago)
      newest = create_score(bill, created_at: 1.day.ago)

      expect { described_class.new.perform }.not_to change { BillInterestingScore.count }
      expect(BillInterestingScore.pluck(:id)).to match_array([recent_superseded.id, newest.id])
    end

    it "keeps the newest row of every bill and deletes only the superseded aged ones" do
      other_bill = create(:bill)

      2.times { create_score(bill, created_at: 40.days.ago) }
      first_bill_newest = create_score(bill, created_at: 35.days.ago)
      2.times { create_score(other_bill, created_at: 40.days.ago) }
      other_bill_newest = create_score(other_bill, created_at: 35.days.ago)

      expect { described_class.new.perform }.to change { BillInterestingScore.count }.from(6).to(2)
      expect(BillInterestingScore.pluck(:id))
        .to match_array([first_bill_newest.id, other_bill_newest.id])
    end

    it "deletes across more than one batch" do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      5.times { create_score(bill, created_at: 40.days.ago) }
      newest = create_score(bill, created_at: 35.days.ago)

      expect(described_class.new.perform).to eq(5)
      expect(BillInterestingScore.pluck(:id)).to eq([newest.id])
    end

    it "deletes nothing when a bill holds a single row" do
      only_row = create_score(bill, created_at: 400.days.ago)

      expect { described_class.new.perform }.not_to change { BillInterestingScore.count }
      expect(BillInterestingScore.pluck(:id)).to eq([only_row.id])
    end

    it "returns zero and logs zero when the table is empty" do
      expect(described_class.new.perform).to eq(0)
      expect(SwayLogging).to have_received(:info).with(/deleted=0/)
    end

    it "logs the deleted count and the retention window" do
      2.times { create_score(bill, created_at: 40.days.ago) }
      create_score(bill, created_at: 35.days.ago)

      described_class.new.perform

      expect(SwayLogging).to have_received(:info)
        .with(/\[BillInterestingScoreRetentionJob\] complete deleted=2 retention_days=30 cutoff_at=/)
    end
  end

  describe "constants" do
    it "encodes the retention window and the batch size" do
      expect(described_class::RETENTION_DAYS).to eq(30)
      expect(described_class::BATCH_SIZE).to eq(1_000)
    end
  end

  it "runs on the background queue" do
    expect(described_class.new.queue_name).to eq("background")
  end
end
