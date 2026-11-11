# frozen_string_literal: true

# @lat: [[pipeline-runs-index-only-surface#Why index precomputes bill counts]]
module PipelineRuns
  class RunSummarySerializer
    type_row_keys = %i[
      id status kind bill_id bill_external_id remote_run_id
      started_at completed_at current_stage
      bills_total bills_succeeded bills_failed failing_stage
    ].freeze
    ROW_KEYS = type_row_keys

    def self.call(scope)
      scope
        .includes(:bill, :pipeline_run_bills, :pipeline_run_stages)
        .map { |run| serialize(run) }
    end

    def self.serialize(run)
      bills = run.pipeline_run_bills.to_a
      stages = run.pipeline_run_stages.to_a
      bill_external_id = run.bill&.external_id
      {
        id: run.id,
        status: run.status,
        # @lat: [[pipeline-runs-index-only-surface#Why index precomputes bill counts#Why a run's kind reads off bill_id, not bill_external_id]]
        kind: run.bill_id.present? ? "single" : "all_bills",
        bill_id: run.bill_id,
        bill_external_id: bill_external_id,
        # @lat: [[legislation-pipeline-run-remote-run-id-history#Two consumers still needed a value]]
        remote_run_id: run.remote_run_id,
        started_at: run.started_at&.utc&.iso8601,
        completed_at: run.completed_at&.utc&.iso8601,
        current_stage: run.current_stage,
        bills_total: bills.length,
        bills_succeeded: bills.count { |b| b.status == "succeeded" },
        bills_failed: bills.count { |b| b.status == "failed" },
        failing_stage: stages.find { |s| s.status == "failed" }&.stage_name
      }
    end
  end
end
