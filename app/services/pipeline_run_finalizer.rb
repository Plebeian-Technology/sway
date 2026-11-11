# frozen_string_literal: true

# @lat: [[llm-summaries#Batch summarisation#One finalizer for the job and the ingest]]
class PipelineRunFinalizer
  # @lat: [[llm-summaries#Batch summarisation#One finalizer for the job and the ingest]]
  def self.call(run:, origin: nil)
    if run.can_mark_succeeded?
      report_bills_nothing_ran_for(run, origin)
      failed_bills = count_failed_bills(run)
      if failed_bills.positive?
        SwayLogging.info(
          "run_legislation_pipeline.partial",
          run_id: run.id,
          failed_bills: failed_bills,
          total_bills: run.pipeline_run_bills.count
        )
        run.mark_partial!
      else
        run.mark_succeeded!
      end
    elsif LegislationPipelineRun::PHASE_52_NON_TERMINAL_STATES.include?(run.status.to_sym)
      SwayLogging.error(
        "run_legislation_pipeline.non_terminal_at_finalize",
        run_id: run.id,
        status: run.status
      )
      run.update_columns(error_message: "non_terminal_at_finalize: status=#{run.status}")
      run.force_fail! if run.can_force_fail?
    end
  end

  # @lat: [[llm-summaries#Batch summarisation#One finalizer for the job and the ingest]]
  def self.count_failed_bills(run)
    failed_clause = RunLegislationPipelineJob::BILL_LEVEL_STAGES
      .map { |stage| "json_extract(stage_results, '$.#{stage}.status') = 'failed'" }
      .join(" OR ")
    run.pipeline_run_bills.where(failed_clause).count
  end

  def self.report_bills_nothing_ran_for(run, origin)
    not_run_bills = count_not_run_bills(run)
    return if not_run_bills.zero?

    SwayLogging.warn(
      "run_legislation_pipeline.bills_not_run",
      run_id: run.id,
      not_run_bills: not_run_bills,
      total_bills: run.pipeline_run_bills.count,
      origin: origin,
      message: "these bills came out of the run with nothing produced — another writer held the " \
        "bill's summary row, or the row was gone. The run itself is not a failure. Resume it to " \
        "come back for them; nothing else does"
    )
  end
  private_class_method :report_bills_nothing_ran_for

  def self.count_not_run_bills(run)
    not_run_clause = RunLegislationPipelineJob::BILL_LEVEL_STAGES
      .map { |stage| "json_extract(stage_results, '$.#{stage}.status') = 'not_run'" }
      .join(" OR ")
    run.pipeline_run_bills.where(not_run_clause).count
  end
end
