# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
RSpec.describe SummaryRunArm do
  let(:bill) { create(:bill) }
  let(:provisioning) { create(:bill_llm_provisioning, bill: bill) }

  describe "a free row" do
    it "reports that the caller may spend" do
      expect(described_class.call(provisioning: provisioning, job_id: "job-1").armed).to be(true)
    end

    it "walks the row into generating" do
      described_class.call(provisioning: provisioning, job_id: "job-1")

      expect(provisioning.reload.generation_status).to eq("generating")
    end

    it "stamps the caller's claim" do
      described_class.call(provisioning: provisioning, job_id: "job-1")

      expect(provisioning.reload.summary_run_id).to eq(SummaryRunMarker.run_claim("job-1"))
    end

    it "writes the caller's extra columns in the same statement as the claim" do
      expires_at = 12.hours.from_now

      described_class.call(
        provisioning: provisioning, job_id: "job-1",
        extra_columns: {summary_batch_id: "msgbatch_x", summary_batch_expires_at: expires_at}
      )

      expect(provisioning.reload.summary_batch_id).to eq("msgbatch_x")
      expect(provisioning.summary_batch_expires_at).to be_within(1.second).of(expires_at)
    end

    it "names the case it took" do
      expect(described_class.call(provisioning: provisioning, job_id: "job-1").decision.name)
        .to eq(:arm_free_row)
    end
  end

  describe "a row another run owns" do
    before do
      provisioning.update_columns(generation_status: "generating", summary_run_id: "run:other")
    end

    it "declines" do
      expect(described_class.call(provisioning: provisioning, job_id: "job-1").armed).to be(false)
    end

    it "writes no extra columns, so the batch does not claim a row it did not arm" do
      described_class.call(
        provisioning: provisioning, job_id: "job-1",
        extra_columns: {summary_batch_id: "msgbatch_x"}
      )

      expect(provisioning.reload.summary_batch_id).to be_nil
    end

    it "carries the declining case out for the caller to log" do
      expect(described_class.call(provisioning: provisioning, job_id: "job-1").decision.name)
        .to eq(:owned_by_another_run)
    end
  end

  describe "a row that was deleted under the lock" do
    it "reports neither armed nor declined" do
      provisioning
      BillLlmProvisioning.where(id: provisioning.id).delete_all

      expect(described_class.call(provisioning: provisioning, job_id: "job-1").armed).to be_nil
    end
  end

  describe "the reclaim hook" do
    it "yields the decision under the lock, so a caller can log a reclaim" do
      provisioning.update_columns(
        generation_status: "generating",
        summary_run_id: "run:dead-worker",
        updated_at: (GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER + 1.hour).ago
      )
      seen = []

      described_class.call(provisioning: provisioning, job_id: "job-1") { |d| seen << d.log_reclaim? }

      expect(seen).to eq([true])
    end

    it "does not yield for a case that declines" do
      provisioning.update_columns(generation_status: "generating", summary_run_id: "run:other")
      seen = []

      described_class.call(provisioning: provisioning, job_id: "job-1") { |d| seen << d.name }

      expect(seen).to be_empty
    end
  end
end
