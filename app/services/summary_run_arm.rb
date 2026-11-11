# frozen_string_literal: true

# @lat: [[llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
class SummaryRunArm
  Outcome = Data.define(:armed, :decision)

  # @lat: [[llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
  def self.call(provisioning:, job_id:, extra_columns: {})
    status_at_load = provisioning.generation_status
    decision = nil #: SummaryRunArmDecision?

    armed = SummaryRunLock.settle_under_lock(provisioning) do
      taken = SummaryRunArmDecision.for(
        provisioning: provisioning, status_at_load: status_at_load, job_id: job_id
      )
      decision = taken
      if taken.proceed?
        yield taken if block_given?

        provisioning.enqueue! if provisioning.can_enqueue?
        provisioning.start_generating! if provisioning.can_start_generating?
        stamp(provisioning, taken, job_id: job_id, extra_columns: extra_columns)
        true
      else
        false
      end
    end

    Outcome.new(armed: armed, decision: decision)
  end

  # @lat: [[llm-summaries#Runs are marked and reclaimable#One armer for both the synchronous run and the batch]]
  def self.stamp(provisioning, decision, job_id:, extra_columns:)
    return unless decision.refresh_clock?

    # @type var columns: Hash[Symbol, untyped]
    columns = {updated_at: Time.current}
    columns[:summary_run_id] = SummaryRunMarker.run_claim(job_id) if decision.claim_row?

    provisioning.update_columns(columns.merge(extra_columns))
  end
  private_class_method :stamp
end
