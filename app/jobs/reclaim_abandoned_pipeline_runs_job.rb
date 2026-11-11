# frozen_string_literal: true

# @lat: [[reclaim-abandoned-pipeline-runs-job-design#Why abandoned? lives on the model, not duplicated at each reader]]
class ReclaimAbandonedPipelineRunsJob < ApplicationJob
  queue_as :background

  # @lat: [[reclaim-jobs-per-row-rescue-pattern#Why the row count per sweep is bounded]]
  MAX_ROWS_PER_SWEEP = 100

  def perform
    candidates = LegislationPipelineRun
      .abandoned_candidates
      .order(:updated_at)
      .limit(MAX_ROWS_PER_SWEEP)

    closed = 0
    skipped = 0
    # @lat: [[reclaim-jobs-per-row-rescue-pattern#Why RecordNotFound is rescued around the lock, not the loop]]
    candidates.each do |run|
      closed += 1 if close(run)
    rescue => e
      skipped += 1
      SwayLogging.log_exception(
        "reclaim_abandoned_pipeline_runs.row_failed",
        exception: e,
        run_id: run.id,
        bill_id: run.bill_id,
        message: "the same row here every tick is a row that needs a person"
      )
    end

    SwayLogging.info(
      "reclaim_abandoned_pipeline_runs.complete",
      closed: closed,
      skipped: skipped,
      abandoned_after_seconds: LegislationPipelineRun::ABANDONED_AFTER.to_i,
      max_rows_per_sweep: MAX_ROWS_PER_SWEEP
    )
    closed
  end

  private

  def close(run)
    # @lat: [[reclaim-abandoned-pipeline-runs-job-design#Why the error message is set, not saved, before force_fail!]]
    run.with_lock do
      next false unless run.abandoned?

      status_before = run.status
      quiet_since = run.updated_at

      next false unless run.can_force_fail?

      run.error_message = abandonment_message(status_before, quiet_since)
      run.force_fail!

      SwayLogging.warn(
        "reclaim_abandoned_pipeline_runs.closed",
        run_id: run.id,
        bill_id: run.bill_id,
        status_before: status_before,
        quiet_since: quiet_since,
        abandoned_after_seconds: LegislationPipelineRun::ABANDONED_AFTER.to_i,
        message: "no worker held this run, so the Run button it was holding off is free again"
      )
      true
    end
  rescue ActiveRecord::RecordNotFound
    # @lat: [[reclaim-jobs-per-row-rescue-pattern#Why RecordNotFound is rescued around the lock, not the loop]]
    false
  end

  # @lat: [[reclaim-abandoned-pipeline-runs-job-design#Why abandonment_message exists as its own method]]
  def abandonment_message(status_before, quiet_since)
    # @lat: [[reclaim-abandoned-pipeline-runs-job-design#Why abandonment_message dashes the stage name]]
    stage = LegislationPipelineRun::STAGE_STATUS_TO_DAG_NAME[status_before]&.tr("_", "-")
    where = stage ? "in the #{stage} stage" : "with status #{status_before}"

    "Closed automatically: this run stopped #{where} and nothing worked on it after " \
      "#{quiet_since.utc.iso8601}. No worker was left carrying it, and while it stayed open no new " \
      "run could start. Resume picks up from the stage it stopped in."
  end
end
