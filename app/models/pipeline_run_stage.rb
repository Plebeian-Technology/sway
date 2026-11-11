# frozen_string_literal: true

# == Schema Information
#
# Table name: legislation_pipeline_run_stages
# Database name: primary
#
#  id                          :integer          not null, primary key
#  completed_bill_external_ids :text             default([]), not null
#  error_message               :text
#  finished_at                 :datetime
#  output_summary              :text
#  remaining_bill_external_ids :text             default([]), not null
#  stage_name                  :string           not null
#  started_at                  :datetime
#  status                      :string           default("pending"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  legislation_pipeline_run_id :integer          not null
#
# Indexes
#
#  idx_on_legislation_pipeline_run_id_c51e3ef6b9  (legislation_pipeline_run_id)
#  index_prs_on_run_and_stage_name                (legislation_pipeline_run_id,stage_name) UNIQUE
#
# Foreign Keys
#
#  legislation_pipeline_run_id  (legislation_pipeline_run_id => legislation_pipeline_runs.id) ON DELETE => cascade
#
class PipelineRunStage < ApplicationRecord
  self.table_name = "legislation_pipeline_run_stages"

  belongs_to :legislation_pipeline_run

  # @lat: [[pipeline-run-stage-design#Why the serialized array columns have no default]]
  serialize :completed_bill_external_ids, coder: JSON
  serialize :remaining_bill_external_ids, coder: JSON
  serialize :output_summary, coder: JSON

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

    event :mark_skipped do
      transition pending: :skipped
    end

    # @lat: [[legislation-pipeline-run-state-machine-design#Why mark_cancelled reaches every per-stage state]]
    event :mark_cancelled do
      transition pending: :cancelled
      transition running: :cancelled
    end
  end

  def completed_bills
    Array(completed_bill_external_ids)
  end

  def remaining_bills
    Array(remaining_bill_external_ids)
  end

  # @lat: [[pipeline-run-stage-design#Why mark_bill_completed! takes a row lock]]
  def mark_bill_completed!(external_id)
    with_lock do
      remaining = Array(remaining_bill_external_ids) #: Array[untyped]
      completed = Array(completed_bill_external_ids) #: Array[untyped]
      return unless remaining.include?(external_id)

      remaining.delete(external_id)
      completed << external_id unless completed.include?(external_id)

      update!(
        remaining_bill_external_ids: remaining,
        completed_bill_external_ids: completed
      )
    end
  end
end
