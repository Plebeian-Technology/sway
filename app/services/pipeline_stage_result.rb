# frozen_string_literal: true

# @lat: [[llm-summaries#Batch summarisation#One stage-result writer for the job and the ingest]]
class PipelineStageResult
  def self.record(bill_run:, stage:, status:, error: nil, reason: nil)
    unless RunLegislationPipelineJob::DAG_ORDER.include?(stage.to_sym)
      raise ArgumentError, "record_stage_result: invalid stage #{stage.inspect} (not in DAG_ORDER)"
    end

    entry = {"status" => status, "at" => Time.current.iso8601} #: Hash[String, String]
    entry["error"] = error if error
    entry["reason"] = reason if reason
    pointer = "$.#{stage}"
    PipelineRunBill
      .where(id: bill_run.id)
      .update_all([
        "stage_results = json_set(COALESCE(stage_results, '{}'), ?, json(?))",
        pointer,
        entry.to_json
      ])
  end
end
