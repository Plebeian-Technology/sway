# frozen_string_literal: true

# @lat: [[llm-summaries#Batch summarisation#Why no job waits on a batch]]
class IngestSummaryBatchesJob < ApplicationJob
  queue_as :background

  # @lat: [[llm-summaries#Batch summarisation#A batch is read back exactly once]]
  limits_concurrency to: 1,
    key: ->(*_args, **_kwargs) { "ingest_summary_batches" },
    duration: 30.minutes,
    on_conflict: :discard

  MAX_RUNS_PER_SWEEP = 25

  def perform
    runs = LegislationPipelineRun.with_pending_summary_batches.order(:id).limit(MAX_RUNS_PER_SWEEP)

    ingested = 0
    skipped = 0
    runs.each do |run|
      SummaryBatchIngest.call(run: run)
      ingested += 1
    rescue => e
      skipped += 1
      SwayLogging.log_exception(
        "ingest_summary_batches.run_failed",
        exception: e,
        run_id: run.id,
        message: "this run's batches could not be read back, and the sweep carried on to the rest — " \
          "the same run here every tick is a run that needs a person"
      )
    end

    SwayLogging.info(
      "ingest_summary_batches.complete",
      runs: ingested,
      skipped: skipped,
      max_runs_per_sweep: MAX_RUNS_PER_SWEEP
    )
    ingested
  end
end
