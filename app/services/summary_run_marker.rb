# frozen_string_literal: true

# @lat: [[run-marker-column-semantics#The three values, and the questions each answers]]
class SummaryRunMarker
  PREFIX = "operator_paste:"

  # @lat: [[run-marker-column-semantics#.run_claim: why it is derived from job_id rather than random]]
  def self.operator_paste = "#{PREFIX}#{SecureRandom.uuid}"

  def self.operator_paste?(value) = value.to_s.start_with?(PREFIX)

  RUN_CLAIM_PREFIX = "run:"

  # @lat: [[run-marker-column-semantics#.run_claim: why it is derived from job_id rather than random]]
  def self.run_claim(job_id) = "#{RUN_CLAIM_PREFIX}#{job_id}"

  def self.run_claim?(value, job_id) = value == run_claim(job_id)

  # @lat: [[run-marker-column-semantics#.purchase_receipt?: why the third shape gets a name here]]
  def self.purchase_receipt?(value, job_id) = value.present? && value == job_id

  BATCH_PREFIX = "batch:"

  # @lat: [[llm-summaries#Batch summarisation#What identity arms a batch-submitted row]]
  def self.batch_run_id(batch_id:, bill_id:) = "#{BATCH_PREFIX}#{batch_id}:#{bill_id}"

  # @lat: [[llm-summaries#Batch summarisation#Why a row is claimed before the batch is bought]]
  def self.batch_pending_id(run_id:, bill_id:) = "#{BATCH_PREFIX}pending:#{run_id}:#{bill_id}"
end
