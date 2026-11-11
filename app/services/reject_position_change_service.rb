# frozen_string_literal: true

# @lat: [[position-change-response-shaping#Why ApprovePositionChangeService and RejectPositionChangeService re-read the row under a lock]]
class RejectPositionChangeService
  def initialize(change:, rejecter:)
    @change = change
    @rejecter = rejecter
  end

  def call
    outcome = :rejected

    OrganizationBillPositionChange.transaction do
      change = OrganizationBillPositionChange.lock.find(@change.id)
      if change.finalized?
        outcome = :already_finalized
        raise ActiveRecord::Rollback
      end

      change.update!(
        status: :rejected,
        rejected_by: @rejecter,
        rejected_at: Time.current
      )
    end

    outcome
  end
end
