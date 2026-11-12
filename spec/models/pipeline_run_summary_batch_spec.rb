# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Batch summarisation#Why chunking is a progress decision, not a cost one]]
# == Schema Information
#
# Table name: legislation_pipeline_run_summary_batches
# Database name: primary
#
#  id                          :integer          not null, primary key
#  attempt                     :integer          default(1), not null
#  canceled_count              :integer          default(0), not null
#  errored_count               :integer          default(0), not null
#  expired_count               :integer          default(0), not null
#  expires_at                  :datetime
#  ingested_at                 :datetime
#  item_count                  :integer          default(0), not null
#  model                       :string
#  submitted_at                :datetime
#  succeeded_count             :integer          default(0), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  batch_id                    :string           not null
#  legislation_pipeline_run_id :integer          not null
#
# Indexes
#
#  index_legislation_pipeline_run_summary_batches_on_batch_id     (batch_id) UNIQUE
#  index_legislation_pipeline_run_summary_batches_on_ingested_at  (ingested_at)
#  index_pipeline_run_summary_batches_on_run_id                   (legislation_pipeline_run_id)
#
# Foreign Keys
#
#  legislation_pipeline_run_id  (legislation_pipeline_run_id => legislation_pipeline_runs.id) ON DELETE => cascade
#
RSpec.describe PipelineRunSummaryBatch, type: :model do
  # @lat: [[explanation/llm-summaries#Batch summarisation#Why the expiry is the server's answer]]
  describe "#live?" do
    it "is false for a batch carrying no expiry at all" do
      batch = create(:pipeline_run_summary_batch, :without_expiry)

      expect(batch.live?).to be(false)
    end

    it "is true while the expiry is still ahead" do
      batch = create(:pipeline_run_summary_batch, expires_at: 1.hour.from_now)

      expect(batch.live?).to be(true)
    end

    it "is false once the expiry has passed" do
      batch = create(:pipeline_run_summary_batch, :expired)

      expect(batch.live?).to be(false)
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#A failed item is retried once, as a batch]]
  describe "#retryable?" do
    it "is true for the batch the run submitted" do
      batch = create(:pipeline_run_summary_batch, attempt: 1)

      expect(batch.retryable?).to be(true)
    end

    it "is false for the retry, which buys no third attempt" do
      batch = create(:pipeline_run_summary_batch, attempt: described_class::MAX_ATTEMPTS)

      expect(batch.retryable?).to be(false)
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#A batch is read back exactly once]]
  describe "#ingested?" do
    it "is false while nothing has read the batch back" do
      batch = create(:pipeline_run_summary_batch)

      expect(batch.ingested?).to be(false)
    end

    it "is true once the read is stamped" do
      batch = create(:pipeline_run_summary_batch, ingested_at: Time.current)

      expect(batch.ingested?).to be(true)
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#Where the per-outcome counts come from]]
  describe "#failed_count" do
    it "sums the errored, canceled and expired counters, leaving the succeeded one out" do
      batch = create(:pipeline_run_summary_batch,
        succeeded_count: 7, errored_count: 2, canceled_count: 3, expired_count: 4)

      expect(batch.failed_count).to eq(9)
    end
  end
end
