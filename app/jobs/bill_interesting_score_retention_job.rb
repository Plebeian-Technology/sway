# frozen_string_literal: true

# @lat: [[bill-interesting-score#Why retention keeps the newest row for each bill]]
class BillInterestingScoreRetentionJob < ApplicationJob
  queue_as :background

  RETENTION_DAYS = 30
  BATCH_SIZE = 1_000

  def perform
    cutoff_at = RETENTION_DAYS.days.ago
    deleted = prune_superseded(cutoff_at)

    SwayLogging.info(
      "[BillInterestingScoreRetentionJob] complete deleted=#{deleted} " \
      "retention_days=#{RETENTION_DAYS} cutoff_at=#{cutoff_at.iso8601}"
    )
    deleted
  end

  private

  def prune_superseded(cutoff_at)
    newest_per_bill = BillInterestingScore.group(:bill_id).select("MAX(id)")
    total = 0
    loop do
      ids = BillInterestingScore
        .where("created_at < ?", cutoff_at)
        .where.not(id: newest_per_bill)
        .limit(BATCH_SIZE)
        .pluck(:id)
      break if ids.empty?

      deleted = BillInterestingScore.where(id: ids).delete_all #: Integer
      total += deleted
      break if ids.size < BATCH_SIZE
    end
    total
  end
end
