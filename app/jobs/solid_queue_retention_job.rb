# frozen_string_literal: true

# @lat: [[solid-queue-retention-job-design#Why prune_failed deletes the child row explicitly]]
class SolidQueueRetentionJob < ApplicationJob
  queue_as :background

  # @lat: [[solid-queue-retention-job-design#Why the retention windows differ]]
  FINISHED_RETENTION_DAYS = 7
  FAILED_RETENTION_DAYS = 30
  # @lat: [[solid-queue-retention-job-design#Why deletes are batched]]
  BATCH_SIZE = 500

  def perform
    finished_deleted = clear_finished
    failed_deleted = prune_failed

    SwayLogging.info(
      "[SolidQueueRetentionJob] complete finished_deleted=#{finished_deleted} " \
      "failed_deleted=#{failed_deleted} finished_retention_days=#{FINISHED_RETENTION_DAYS} " \
      "failed_retention_days=#{FAILED_RETENTION_DAYS}"
    )
    finished_deleted + failed_deleted
  end

  private

  # @lat: [[solid-queue-retention-job-design#Why clear_finished uses plain ActiveRecord instead of the gem's batching method]]
  def clear_finished
    cutoff = FINISHED_RETENTION_DAYS.days.ago
    total = 0
    loop do
      ids = SolidQueue::Job
        .where.not(finished_at: nil)
        .where("finished_at < ?", cutoff)
        .limit(BATCH_SIZE)
        .pluck(:id)
      break if ids.empty?

      deleted = SolidQueue::Job.where(id: ids).delete_all #: Integer
      total += deleted
      break if ids.size < BATCH_SIZE
    end
    total
  end

  # @lat: [[solid-queue-retention-job-design#Why prune_failed deletes the child row explicitly]]
  def prune_failed
    cutoff = FAILED_RETENTION_DAYS.days.ago
    total = 0
    loop do
      job_ids = SolidQueue::FailedExecution
        .where("created_at < ?", cutoff)
        .limit(BATCH_SIZE)
        .pluck(:job_id)
      break if job_ids.empty?

      SolidQueue::Job.transaction do
        SolidQueue::FailedExecution.where(job_id: job_ids).delete_all
        deleted = SolidQueue::Job.where(id: job_ids, finished_at: nil).delete_all #: Integer
        total += deleted
      end
      break if job_ids.size < BATCH_SIZE
    end
    total
  end
end
