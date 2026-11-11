# frozen_string_literal: true

# @lat: [[arm-decision-table#decide: why the paste test runs ahead of the status and the clock]]
class SummaryRunArmDecision
  GENERATING = "generating"

  # @lat: [[arm-decision-table#decide: why the paste test runs ahead of the status and the clock]]
  PENDING = "pending"

  # @lat: [[arm-decision-table#Why CLAIMING excludes the two markers the arm may not destroy]]
  CASES = %i[
    row_moved
    paste_hand_off
    paste_already_settled
    own_claim
    resume_after_purchase
    reclaim_abandoned
    owned_by_another_run
    arm_after_purchase
    arm_free_row
  ].freeze

  DECLINED = %i[row_moved paste_already_settled owned_by_another_run].freeze

  # @lat: [[arm-decision-table#Why CLAIMING excludes the two markers the arm may not destroy]]
  CLAIMING = %i[own_claim reclaim_abandoned arm_free_row].freeze

  attr_reader :name

  def self.for(provisioning:, status_at_load:, job_id:)
    new(
      status_at_load: status_at_load,
      status: provisioning.generation_status,
      marker: provisioning.summary_run_id,
      updated_at: provisioning.updated_at,
      job_id: job_id
    )
  end

  def initialize(status_at_load:, status:, marker:, updated_at:, job_id:)
    @name = decide(
      status_at_load: status_at_load,
      status: status,
      marker: marker,
      updated_at: updated_at,
      job_id: job_id
    )
  end

  def proceed? = !DECLINED.include?(@name)

  def claim_row? = CLAIMING.include?(@name)

  # @lat: [[arm-decision-table#decide: why the paste test runs ahead of the status and the clock]]
  def refresh_clock? = proceed?

  # @lat: [[arm-decision-table#log_reclaim?: why it fires for exactly one case]]
  def log_reclaim? = @name == :reclaim_abandoned

  private

  def decide(status_at_load:, status:, marker:, updated_at:, job_id:)
    return :row_moved if status != status_at_load

    # @lat: [[arm-decision-table#decide: why the paste test runs ahead of the status and the clock]]
    if SummaryRunMarker.operator_paste?(marker)
      return :paste_hand_off if status == GENERATING || status == PENDING

      return :paste_already_settled
    end

    if status == GENERATING
      return :own_claim if SummaryRunMarker.run_claim?(marker, job_id)
      return :resume_after_purchase if SummaryRunMarker.purchase_receipt?(marker, job_id)
      return :reclaim_abandoned if abandoned?(updated_at)

      return :owned_by_another_run
    end

    return :arm_after_purchase if SummaryRunMarker.purchase_receipt?(marker, job_id)

    :arm_free_row
  end

  # @lat: [[arm-decision-table#abandoned?: the shared constant, and why a nil timestamp is not abandoned]]
  def abandoned?(updated_at)
    updated_at.present? && updated_at <= GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER.ago
  end
end
