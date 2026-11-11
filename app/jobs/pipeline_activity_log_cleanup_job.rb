# frozen_string_literal: true

# @lat: [[pipeline-activity-log-cleanup-delete-all-callback-skip#Why the job's retention rule excludes rows by both subject_type and subject_id]]
class PipelineActivityLogCleanupJob < ApplicationJob
  queue_as :background

  RETENTION_DAYS = 30
  RECENT_RUNS_PRESERVED = 50

  def perform
    cutoff_at = RETENTION_DAYS.days.ago
    preserved_run_ids = LegislationPipelineRun
      .order(created_at: :desc)
      .limit(RECENT_RUNS_PRESERVED)
      .pluck(:id)

    aged = PipelineActivityLogEntry.where("created_at < ?", cutoff_at)

    # @lat: [[pipeline-activity-log-cleanup-delete-all-callback-skip#Why the job's retention rule excludes rows by both subject_type and subject_id]]
    delete_scope =
      if preserved_run_ids.empty?
        aged
      else
        aged.where.not(
          subject_type: "LegislationPipelineRun",
          subject_id: preserved_run_ids
        )
      end

    # @lat: [[pipeline-activity-log-cleanup-delete-all-callback-skip#Why PipelineActivityLogEntry must never gain a destroy callback]]
    deleted = delete_scope.delete_all

    SwayLogging.info(
      "[PipelineActivityLogCleanupJob] complete deleted=#{deleted} " \
      "preserved_run_ids_count=#{preserved_run_ids.size} cutoff_at=#{cutoff_at.iso8601}"
    )
    deleted
  end
end
