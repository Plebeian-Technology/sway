# frozen_string_literal: true

# @lat: [[abandoned-run-reclaim#Why ReclaimAbandonedSummaryRunsJob exists]]
class ReclaimAbandonedSummaryRunsJob < ApplicationJob
  queue_as :background

  # @lat: [[reclaim-jobs-per-row-rescue-pattern#Why the row count per sweep is bounded]]
  MAX_ROWS_PER_SWEEP = 200

  def perform
    cutoff_at = GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER.ago

    # @lat: [[abandoned-run-reclaim#Why reclaim narrows in SQL first, then re-checks under the lock]]
    candidates = BillLlmProvisioning
      .reclaimable_candidates
      .order(:updated_at)
      .limit(MAX_ROWS_PER_SWEEP)

    reclaimed = 0
    skipped = 0
    # @lat: [[reclaim-jobs-per-row-rescue-pattern#Why RecordNotFound is rescued around the lock, not the loop]]
    candidates.each do |provisioning|
      reclaimed += 1 if reclaim(provisioning)
    rescue => e
      skipped += 1
      SwayLogging.log_exception(
        "reclaim_abandoned_summary_runs.row_failed",
        exception: e,
        provisioning_id: provisioning.id,
        bill_id: provisioning.bill_id,
        message: "this row could not be freed, and the sweep carried on to the rest — a repeat " \
          "of the same row here every tick is a row that needs a person"
      )
    end

    SwayLogging.info(
      "reclaim_abandoned_summary_runs.complete",
      reclaimed: reclaimed,
      skipped: skipped,
      cutoff_at: cutoff_at.iso8601,
      max_rows_per_sweep: MAX_ROWS_PER_SWEEP
    )
    reclaimed
  end

  private

  def reclaim(provisioning)
    # @lat: [[abandoned-run-reclaim#Why reclaim narrows in SQL first, then re-checks under the lock]]
    provisioning.with_lock do
      status_before = provisioning.generation_status
      abandoned_since = provisioning.updated_at

      outcome = SummaryRunRelease.call(provisioning, rearmed_by_caller: false)
      next false if outcome == :not_reclaimable

      SwayLogging.warn(
        "reclaim_abandoned_summary_runs.reclaimed",
        provisioning_id: provisioning.id,
        bill_id: provisioning.bill_id,
        generation_status: status_before,
        outcome: outcome,
        abandoned_since: abandoned_since,
        reclaim_after_seconds: GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER.to_i,
        message: "no writer touched this row for longer than the job's worst-case wall clock, so " \
          "the run that claimed it is gone — `released` moved it to a terminal status the " \
          "operator's own controls can act on, `handed_off` finished a summary a human had " \
          "already pasted onto it"
      )
      true
    end
  rescue ActiveRecord::RecordNotFound
    # @lat: [[reclaim-jobs-per-row-rescue-pattern#Why RecordNotFound is rescued around the lock, not the loop]]
    false
  end
end
