# frozen_string_literal: true

# == Schema Information
#
# Table name: legislation_pipeline_run_bills
# Database name: primary
#
#  id                          :integer          not null, primary key
#  error_message               :text
#  finished_at                 :datetime
#  sort_order                  :integer          default(0), not null
#  stage_results               :json             not null
#  started_at                  :datetime
#  status                      :string           default("pending"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  bill_external_id            :string           not null
#  legislation_pipeline_run_id :integer          not null
#
# Indexes
#
#  idx_on_legislation_pipeline_run_id_1cc054cf9b             (legislation_pipeline_run_id)
#  index_legislation_pipeline_run_bills_on_bill_external_id  (bill_external_id)
#  index_prb_on_run_and_bill_external_id                     (legislation_pipeline_run_id,bill_external_id) UNIQUE
#
# Foreign Keys
#
#  legislation_pipeline_run_id  (legislation_pipeline_run_id => legislation_pipeline_runs.id) ON DELETE => cascade
#
class PipelineRunBill < ApplicationRecord
  self.table_name = "legislation_pipeline_run_bills"

  belongs_to :legislation_pipeline_run

  # @lat: [[pipeline-run-bill-lifecycle#Why sort_order cannot change once set]]
  validate :sort_order_monotonic, on: :update

  TERMINAL_BILL_STATUSES = %w[succeeded failed skipped].freeze

  # @lat: [[pipeline-run-bill-status-column#PipelineRunBill's status column is a coarse summary]]

  state_machine :status, initial: :pending do
    event :start_running do
      transition pending: :running
    end

    event :mark_succeeded do
      transition running: :succeeded
    end

    event :mark_failed do
      transition pending: :failed
      transition running: :failed
    end

    # @lat: [[pipeline-run-bill-lifecycle#Why LegislationPipelineRun's pipeline_run_bills association orders by sort_order]]
    event :mark_skipped do
      transition pending: :skipped
    end

    # @lat: [[pipeline-run-bill-lifecycle#Why LegislationPipelineRun's pipeline_run_bills association orders by sort_order]]
    before_transition any => :running do |bill_run, _|
      bill_run.started_at ||= Time.current
    end

    before_transition any => [:succeeded, :failed, :skipped] do |bill_run, _|
      bill_run.finished_at ||= Time.current
    end

    # @lat: [[pipeline-run-bill-lifecycle#The after_transition and after_commit hooks follow the run-level pattern]]
    after_transition any => any do |bill_run, transition|
      # @lat: [[pipeline-activity-log-auto-included-stage-context#LegislationPipelineRun's audit-log transaction guarantee]]
      next if transition.from.nil?

      PipelineActivityLogger.emit_bill_transition!(
        bill_run: bill_run,
        from: transition.from,
        to: transition.to,
        event: transition.event
      )
    end
  end

  # @lat: [[pipeline-run-bill-lifecycle#The after_transition and after_commit hooks follow the run-level pattern]]
  after_commit on: :update do
    if saved_change_to_status?
      from, to = saved_change_to_status
      PipelineRunBroadcast.deliver(
        legislation_pipeline_run&.remote_run_id || "global",
        {
          scope: "bill",
          run_id: legislation_pipeline_run_id,
          bill_run_id: id,
          bill_external_id: bill_external_id,
          status: status,
          event: nil,
          from: from,
          to: to
        },
        log_event: "pipeline_run_bill.status_broadcast_failed",
        run_id: legislation_pipeline_run_id,
        bill_run_id: id
      )
    end
  end

  private

  # @lat: [[pipeline-run-bill-lifecycle#Why sort_order cannot change once set]]
  def sort_order_monotonic
    return unless will_save_change_to_sort_order?
    return if sort_order_was.nil?

    errors.add(:sort_order, "cannot change once persisted")
  end
end
