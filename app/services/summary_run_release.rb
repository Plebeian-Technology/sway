# frozen_string_literal: true

# @lat: [[summary-run-release-single-home#The rule the single home enforces]]
class SummaryRunRelease
  # @lat: [[summary-run-release-message-history#The rule both sentences follow]]
  # @lat: [[summary-run-release-message-invariants#Preconditions]]
  RELEASED_UNSTARTED_ERROR =
    "This summary run never started. Nothing wrote to it for over " \
    "#{GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER.inspect}, so Sway released it. " \
    "It made no calls, so nothing was charged, and anything you typed was saved. Any summary " \
    "on this bill was already there before this run. Try again when you are ready."

  RELEASED_IN_FLIGHT_ERROR =
    "This summary run stopped part-way. Nothing wrote to it for over " \
    "#{GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER.inspect}, so Sway released it. " \
    "It may already have paid for a call, and it may have saved part of its work. Anything you " \
    "typed was saved. Check what is on this bill before you try again."

  def self.call(provisioning, rearmed_by_caller:)
    return :not_reclaimable unless provisioning.reclaimable?

    return hand_off_paste!(provisioning) if
      !rearmed_by_caller && SummaryRunMarker.operator_paste?(provisioning.summary_run_id)

    unless rearmed_by_caller
      # @lat: [[summary-run-release-message-invariants#Clause by clause]]
      message = provisioning.generating? ? RELEASED_IN_FLIGHT_ERROR : RELEASED_UNSTARTED_ERROR
      provisioning.update_columns(
        generation_error: message[0, GenerateBillSummaryJob::MAX_GENERATION_ERROR_LENGTH]
      )
    end

    provisioning.generating? ? provisioning.mark_failed! : provisioning.mark_skipped!
    :released
  end

  # @lat: [[summary-run-release-hand-off-paste#Why a stale generation_error is cleared before the hand-off completes]]
  def self.hand_off_paste!(provisioning)
    # @lat: [[summary-run-release-hand-off-paste#Why a stale generation_error is cleared before the hand-off completes]]
    provisioning.update_columns(generation_error: nil) if provisioning.generation_error.present?

    provisioning.start_generating! if provisioning.can_start_generating?
    provisioning.mark_completed! if provisioning.can_mark_completed?
    :handed_off
  end
end
