# frozen_string_literal: true

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
# @lat: [[llm-summaries#Batch summarisation#Why chunking is a progress decision, not a cost one]]
class PipelineRunSummaryBatch < ApplicationRecord
  self.table_name = "legislation_pipeline_run_summary_batches"

  belongs_to :legislation_pipeline_run

  validates :batch_id, presence: true

  scope :live, -> { where("expires_at > ?", Time.current) }

  # @lat: [[llm-summaries#Batch summarisation#A batch is read back exactly once]]
  scope :pending_ingest, -> { where(ingested_at: nil) }
  scope :ingested, -> { where.not(ingested_at: nil) }

  # @lat: [[llm-summaries#Batch summarisation#A failed item is retried once, as a batch]]
  FIRST_ATTEMPT = 1
  MAX_ATTEMPTS = 2

  def live?
    expiry = expires_at
    return false if expiry.nil?

    expiry > Time.current
  end

  def ingested? = ingested_at.present?

  def retryable? = attempt < MAX_ATTEMPTS

  def failed_count = errored_count + canceled_count + expired_count
end
