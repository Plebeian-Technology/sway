# frozen_string_literal: true

# @lat: [[llm-summaries#Batch summarisation#One settle shared by the job and the ingest]]
class SummaryRunSettle
  # @lat: [[llm-summaries#Batch summarisation#One settle shared by the job and the ingest]]
  def self.completed!(bill, provisioning, clear_generation_error: false, recompute_score: true)
    settled = SummaryRunLock.settle_under_lock(provisioning) do
      if provisioning.generating?
        provisioning.update_columns(generation_error: nil) if clear_generation_error
        provisioning.mark_completed!
        true
      else
        false
      end
    end
    return unless settled

    RecomputeBillInterestingScoreJob.perform_later(bill.id) if recompute_score

    SwayLogging.info(
      "generate_bill_summary.success",
      bill_id: bill.id,
      provisioning_id: provisioning.id
    )
  end
end
