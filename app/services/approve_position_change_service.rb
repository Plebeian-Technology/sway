# frozen_string_literal: true

# @lat: [[position-change-response-shaping#Why ApprovePositionChangeService and RejectPositionChangeService re-read the row under a lock]]
class ApprovePositionChangeService
  def initialize(change:, approver:)
    @change = change
    @approver = approver
  end

  def call
    outcome = :approved
    failure_errors = nil

    OrganizationBillPositionChange.transaction do
      change = OrganizationBillPositionChange.lock.find(@change.id)
      if change.finalized?
        outcome = :already_finalized
        raise ActiveRecord::Rollback
      end

      if change.update(approved_by: @approver, status: :approved)
        position = change.organization_bill_position
        position.support = OrganizationBillPosition.normalize_support(change.new_support) || change.new_support
        position.summary = change.new_summary
        position.active = true
        position.save!
      else
        outcome = :approve_failed
        failure_errors = change.errors.full_messages
        raise ActiveRecord::Rollback
      end
    end

    SwayLogging.error("approve_position_change.approve_failed", errors: failure_errors) if outcome == :approve_failed
    outcome
  end
end
