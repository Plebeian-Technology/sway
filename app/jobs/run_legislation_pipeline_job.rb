# frozen_string_literal: true

# @lat: [[legislation-pipeline-job#How it behaves]]
class RunLegislationPipelineJob < ApplicationJob
  queue_as :background

  # @lat: [[legislation-pipeline#Runs, resume and restart#Queue ownership outlives an operator stop]]
  limits_concurrency to: 1,
    key: ->(*_args, **_kwargs) { "legislation_pipeline_global" },
    duration: 4.hours,
    on_conflict: :block

  discard_on ActiveRecord::RecordNotFound

  # @lat: [[legislation-pipeline-no-retry-on-network#Why RunLegislationPipelineJob has no retry_on for network errors]]
  RUN_LEVEL_STAGES = [:fetch_bills, :fetch_law].freeze

  BILL_LEVEL_STAGES = [:extract_text, :parse_sections, :generate_diffs,
    :fetch_hearings, :clean_testimony, :summarize].freeze

  STAGE_SERVICES = {
    fetch_bills: "FetchBillsService",
    fetch_law: "FetchLawService",
    extract_text: nil,
    parse_sections: "ParseSectionsService",
    generate_diffs: "GenerateDiffsService",
    fetch_hearings: "FetchHearingsService",
    clean_testimony: "Testimony::CleanAndGroupService",
    summarize: nil
  }.freeze

  # @lat: [[run-legislation-pipeline-job-internals#Why INLINE_DISPATCH_STAGES and the boot-time integrity check exist]]
  INLINE_DISPATCH_STAGES = [:extract_text, :summarize].freeze

  nil_service_stages = STAGE_SERVICES.select { |_, svc| svc.nil? }.keys.sort
  expected_inline_stages = INLINE_DISPATCH_STAGES.sort
  if nil_service_stages != expected_inline_stages
    raise "RunLegislationPipelineJob: STAGE_SERVICES nil-service stages " \
      "(#{nil_service_stages.inspect}) drift from INLINE_DISPATCH_STAGES " \
      "(#{expected_inline_stages.inspect})"
  end

  # @lat: [[run-legislation-pipeline-job-internals#Why fetch_law runs before extract_text in DAG_ORDER]]
  DAG_ORDER = [
    :fetch_bills,
    :fetch_law,
    :extract_text,
    :parse_sections,
    :generate_diffs,
    :fetch_hearings,
    :clean_testimony,
    :summarize
  ].freeze

  CONSECUTIVE_FAILURE_BUDGET = 5

  # @lat: [[llm-summaries#Batch summarisation#Why no job waits on a batch]]
  AWAITING_SUMMARY_BATCH = :awaiting_summary_batch

  # @lat: [[run-legislation-pipeline-job-internals#Why ORIGIN_VALUES exists and unknown values are logged, not rejected]]
  ORIGIN_VALUES = %w[fresh resume restart seed].freeze

  # @lat: [[legislation-pipeline#Runs, resume and restart]]
  def perform(run_id, origin: "fresh")
    run = find_pipeline_run(run_id)
    return unless run

    # @lat: [[bill-session-archiving#Bill session archiving#Pipeline and archive exclusion]]
    PipelineLocaleLock.with_locale(run.effective_sway_locale&.id || run.sway_locale_id) do
      run = find_pipeline_run(run_id)
      execute_pipeline_run(run, origin) if run
    end
  rescue OperatorAbortError => e
    # @lat: [[legislation-pipeline#Runs, resume and restart]]
    SwayLogging.info(
      "run_legislation_pipeline.operator_aborted",
      run_id: run_id,
      stage: e.stage,
      processed_count: e.processed_count,
      terminal_status: e.terminal_status
    )
  rescue StateMachines::InvalidTransition => e
    # @lat: [[legislation-pipeline#Runs, resume and restart]]
    SwayLogging.warn(
      "run_legislation_pipeline.invalid_transition_terminal",
      run_id: run_id, message: e.message
    )
    handle_run_failure(run, e)
    raise StageError, "run-level invalid state transition: #{e.message.to_s[0, 500]}"
  rescue StageError => e
    handle_run_failure(run, e)
    raise
  rescue => e
    SwayLogging.error("run_legislation_pipeline.fatal", run_id: run_id, exception: e.class.name, message: e.message)
    handle_run_failure(run, e)
    raise
  end

  private

  def execute_pipeline_run(run, origin)
    return unless prepare_pipeline_run!(run, origin: origin)

    # @lat: [[legislation-pipeline#Runs, resume and restart#Auto-include dependencies are resolved once before the stage loop]]
    auto_included_set = Pipeline::StageDeps.transitive_closure(run.stages.map(&:to_s)) - run.stages

    remaining_stages = stages_to_run(run, origin)
    until remaining_stages.empty?
      stage = remaining_stages.shift
      auto_included = auto_included_set.include?(Pipeline::StageKeys.to_key(stage))

      awaiting_batch = execute_stage!(run, stage, auto_included: auto_included)
      break if awaiting_batch
    end

    finalize_pipeline_run!(run)
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart#Queue ownership outlives an operator stop]]
  def check_run_active!(run, stage:, processed_count: 0)
    run.reload
    return if LegislationPipelineRun::PHASE_52_NON_TERMINAL_STATES.include?(run.status.to_sym)

    raise OperatorAbortError.new(stage: stage, processed_count: processed_count, terminal_status: run.status)
  end

  # @lat: [[stages-to-run-algorithm#What it does]]
  # @lat: [[stages-to-run-history#Why stages_to_run reads run.stages]]
  def stages_to_run(run, origin)
    selected_symbols = run.stages.map { |k| Pipeline::StageKeys.to_symbol(k) }

    candidate_set =
      if run.download_missing_assets
        closure_keys = Pipeline::StageDeps.transitive_closure(run.stages.map(&:to_s))
        closure_keys.map { |k| Pipeline::StageKeys.to_symbol(k) }.to_set | selected_symbols.to_set
      else
        selected_symbols.to_set
      end

    ordered = DAG_ORDER.select { |sym| candidate_set.include?(sym) }
    return ordered if origin != "resume"

    completed = succeeded_stage_names_before(run)
    ordered.reject { |s| completed.include?(s.to_s) }
  end

  # @lat: [[resume-stage-history-walk#Why the "filters out stages the resumed run already finished" fixture puts the succeeded row on the PARENT run]]
  def succeeded_stage_names_before(run)
    names = Set.new #: Set[String]
    seen = Set.new #: Set[Integer]
    # @type var current: LegislationPipelineRun?
    current = run.parent_run

    while current && !seen.include?(current.id)
      seen << current.id
      names.merge(
        current.pipeline_run_stages.where(status: "succeeded").pluck(:stage_name).map(&:to_s)
      )
      current = current.parent_run
    end

    names
  end

  # @lat: [[run-legislation-pipeline-job-internals#Why service_mode_for is a named method]]
  def run_level_service_kwargs(run, stage, auto_included:)
    base = {run: run} #: Hash[Symbol, untyped]
    base[:mode] = service_mode_for(auto_included) if stage == :fetch_bills
    base
  end

  # @lat: [[run-legislation-pipeline-job-internals#Why service_mode_for is a named method]]
  def service_mode_for(auto_included)
    auto_included ? :backfill_missing : :discover
  end

  # @lat: [[run-legislation-pipeline-job-internals#Why bills_triggering_auto_include returns an empty array for RUN_LEVEL stages]]
  def bills_triggering_auto_include(run, stage_sym)
    unless BILL_LEVEL_STAGES.include?(stage_sym)
      empty = [] #: Array[String]
      return empty
    end

    stage_key = Pipeline::StageKeys.to_key(stage_sym)
    missing = [] #: Array[String]
    run.each_pipeline_run_bill do |bill_run|
      bill = resolve_bill(bill_run)
      next if bill.nil?

      missing << bill_run.bill_external_id unless Pipeline::ArtifactPresence.present?(stage_key, bill: bill)
    end
    missing
  end

  # @lat: [[pipeline-run-bills-seeding#All-bills runs, from disk]]
  def pre_seed_single_bill_pipeline_run_bill!(run)
    return if run.bill_id.nil?

    bill = run.bill
    return if bill.nil?

    PipelineRunBill.find_or_create_by!(
      legislation_pipeline_run_id: run.id,
      bill_external_id: bill.external_id
    ) do |bill_run|
      bill_run.status = "pending"
      bill_run.sort_order = 0
      bill_run.stage_results = {}
    end
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart#Hydrated runs include database-only bills in the selected locale]]
  def hydrate_pipeline_run_bills_from_disk!(run)
    return unless run.bill_id.nil?
    return if run.stages.map(&:to_s).include?("fetch-bills")
    return if run.pipeline_run_bills.exists?

    seeded = FetchBillsService.new(run: run).seed_from_disk
    if run.effective_sway_locale
      next_sort_order = (PipelineRunBill.where(legislation_pipeline_run_id: run.id).maximum(:sort_order) || -1) + 1
      existing_bills = Bill.where(sway_locale: run.effective_sway_locale).order(:id)
      existing_bills.each do |bill|
        PipelineRunBill.find_or_create_by!(
          legislation_pipeline_run_id: run.id,
          bill_external_id: bill.external_id
        ) do |prb|
          prb.sort_order = next_sort_order
          next_sort_order += 1
          prb.status = "pending"
          prb.stage_results = {}
        end
      end
    end
    total_seeded = [seeded, PipelineRunBill.where(legislation_pipeline_run_id: run.id).count].max
    return if total_seeded.zero?

    run.pipeline_run_bills.reset

    SwayLogging.info(
      "run_legislation_pipeline.hydrated_from_disk",
      run_id: run.id,
      seeded_count: total_seeded
    )
  end

  # @lat: [[resume-stuck-stage-reset#The pipeline_run_stages row is reset too]]
  # @lat: [[explanation/llm-summaries#Batch summarisation#Why resume draws the same line as abandonment]]
  def normalize_for_resume(run)
    return false if run.nil?

    stuck_states = LegislationPipelineRun::PHASE_52_STAGE_STATES.map(&:to_s)
    current_status = run.status.to_s
    return false unless stuck_states.include?(current_status)

    if run.summary_batch_awaited?
      PipelineActivityLogger.log_resume_deferred_for_summary_batch!(run: run)
      return true
    end

    stuck_stage = stage_name_for_status(current_status)
    SwayLogging.warn(
      "[RunLegislationPipelineJob] normalizing stuck status #{current_status.inspect} → 'running' for run ##{run.id} (stuck stage: #{stuck_stage.inspect})"
    )

    ::ActiveRecord::Base.transaction do
      # @lat: [[run-legislation-pipeline-job-internals#Why normalize_for_resume writes the status column directly, bypassing the state machine]]
      run.reopen_stuck_stage!
      # @lat: [[run-legislation-pipeline-job-internals#Why normalize_for_resume also resets non-succeeded stage rows]]
      unless stuck_stage.nil?
        run.pipeline_run_stages
          .where(stage_name: stuck_stage)
          .where.not(status: "succeeded")
          .update_all(status: "pending", started_at: nil, finished_at: nil)
      end
    end
    false
  end

  # @lat: [[run-legislation-pipeline-job-internals#Why stage_name_for_status delegates and never raises]]
  def stage_name_for_status(status)
    LegislationPipelineRun::STAGE_STATUS_TO_DAG_NAME[status.to_s]
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart]]
  def find_pipeline_run(pipeline_run_id)
    run = LegislationPipelineRun.find_by(id: pipeline_run_id)
    return nil if run.nil?
    return nil if LegislationPipelineRun::TERMINAL_STATUSES.map(&:to_s).include?(run.status.to_s)

    run
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart]]
  def prepare_pipeline_run!(run, origin: nil)
    @origin = origin.to_s
    unless ORIGIN_VALUES.include?(origin.to_s)
      SwayLogging.warn(
        "run_legislation_pipeline.unknown_origin",
        run_id: run.id, origin: origin
      )
    end
    SwayLogging.info("run_legislation_pipeline.start", run_id: run.id, origin: origin)
    return false if origin == "resume" && normalize_for_resume(run)

    run.start_running! if run.can_start_running?

    pre_seed_single_bill_pipeline_run_bill!(run)
    hydrate_pipeline_run_bills_from_disk!(run)
    true
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart#Discrete stage execution encapsulates dispatch and failure boundaries]]
  def finalize_pipeline_run!(run)
    # @lat: [[llm-summaries#Batch summarisation#Why no job waits on a batch]]
    return if run.status == "awaiting_summary_batch"

    finalize_run_terminal_state(run)
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart#Discrete stage execution encapsulates dispatch and failure boundaries]]
  def execute_stage!(run, stage, auto_included: false)
    check_run_active!(run, stage: stage)

    # @lat: [[legislation-pipeline#Runs, resume and restart#Auto-include execution context is scoped and cleared in ensure]]
    if auto_included
      Pipeline::Current.current_auto_include_context = {
        stage: Pipeline::StageKeys.to_key(stage),
        reason: "missing_artifact",
        bill_external_ids: bills_triggering_auto_include(run, stage)
      }
    end

    awaiting_batch = false
    begin
      run.public_send(:"start_#{stage}!") if run.respond_to?(:"can_start_#{stage}?") && run.public_send(:"can_start_#{stage}?")

      if RUN_LEVEL_STAGES.include?(stage)
        run_run_level_stage(run, stage, auto_included: auto_included)
      elsif BILL_LEVEL_STAGES.include?(stage)
        awaiting_batch = run_bill_level_stage(run, stage, auto_included: auto_included) == AWAITING_SUMMARY_BATCH
      else
        raise StageError, "stage #{stage} is not classified as RUN_LEVEL or BILL_LEVEL"
      end

      check_run_active!(run, stage: stage)

      # @lat: [[llm-summaries#Batch summarisation#Why no job waits on a batch]]
      if awaiting_batch
        run.await_summary_batch! if run.can_await_summary_batch?
      elsif run.respond_to?(:"can_complete_#{stage}?") && run.public_send(:"can_complete_#{stage}?")
        run.public_send(:"complete_#{stage}!")
      end
    rescue StateMachines::InvalidTransition => e
      SwayLogging.warn(
        "run_legislation_pipeline.invalid_transition",
        run_id: run.id, stage: stage, message: e.message
      )
      # @lat: [[legislation-pipeline#Runs, resume and restart#Per-stage invalid transitions fail the run immediately]]
      raise StageError, "stage #{stage} invalid state transition: #{e.message.to_s[0, 500]}"
    ensure
      # @lat: [[legislation-pipeline#Runs, resume and restart#Auto-include execution context is scoped and cleared in ensure]]
      Pipeline::Current.current_auto_include_context = nil if auto_included
    end

    awaiting_batch
  end

  def run_run_level_stage(run, stage, auto_included: false)
    klass = STAGE_SERVICES[stage]
    raise StageError, "RUN_LEVEL stage #{stage} has no service class" unless klass

    service_class = klass #: String
    service_class.constantize.new(**run_level_service_kwargs(run, stage, auto_included: auto_included)).call
  rescue StageError
    raise
  rescue Faraday::Error => e
    raise StageError, "#{stage} (run-level) network failure: #{e.class.name}: #{e.message.to_s[0, 500]}"
  # @lat: [[run-legislation-pipeline-job-internals#Why run_run_level_stage rewraps a stray BillProcessingError-shaped failure as StageError]]
  rescue BillProcessingError => e
    if e.message.start_with?("fetch_bills", "fetch_law") ||
        e.message.include?("No active session found") ||
        e.message.include?("Congress.gov HTTP") ||
        e.message.include?("no bills were discovered")
      raise StageError, e.message
    else
      SwayLogging.warn("[RunLegislationPipelineJob] #{stage} per-row error bypassed run failure: #{e.message}")
    end
  rescue => e
    # @lat: [[legislation-pipeline#Runs, resume and restart#A stage that produced nothing is not a success]]
    SwayLogging.log_exception("run_legislation_pipeline.run_level_stage_rewrapped", exception: e, stage: stage)
    raise StageError, "#{stage} (run-level) failed: #{e.class.name}: #{e.message.to_s[0, 500]}"
  end

  def run_bill_level_stage(run, stage, auto_included: false)
    consecutive_failures = 0

    # @lat: [[run-legislation-pipeline-job-internals#Inside run_bill_level_stage#Why the environment is preflighted before the per-bill loop]]
    preflight_stage_environment!(stage)

    # @lat: [[run-legislation-pipeline-job-internals#Inside run_bill_level_stage#Why stage_key is computed once before the loop]]
    stage_key = Pipeline::StageKeys.to_key(stage)
    # @lat: [[llm-summaries#Batch summarisation#Which runs submit a batch at all]]
    submission = (stage == :summarize) ? SummaryBatchSubmission.for(run: run) : nil
    processed_count = 0
    # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#The summarize stage logs per-bill progress]]
    total_bills = run.pipeline_run_bills.count
    stage_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    SwayLogging.info(
      "run_legislation_pipeline.stage_start",
      run_id: run.id, stage: stage, bills: total_bills, origin: @origin
    )
    run.each_pipeline_run_bill do |bill_run|
      check_run_active!(run, stage: stage, processed_count: processed_count)

      next if stage_already_succeeded?(bill_run, stage)

      # @lat: [[run-legislation-pipeline-job-internals#Inside run_bill_level_stage#Why the artifact-aware skip gate only applies to auto-included stages]]
      if auto_included
        bill = resolve_bill(bill_run)
        if bill && Pipeline::ArtifactPresence.present?(stage_key, bill: bill)
          record_stage_result(bill_run, stage, "skipped", reason: "artifact_present")
          bill_run.start_running! if bill_run.can_start_running?
          bill_run.mark_succeeded! if bill_run.can_mark_succeeded?
          next
        end
      end

      processed_count += 1
      bill_run.start_running! if bill_run.can_start_running?
      bill_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        if submission
          # @lat: [[llm-summaries#Batch summarisation#Not every bill earns a batch item]]
          submission.accumulate(bill_run, resolve_bill!(bill_run))
          consecutive_failures = 0
          next
        end

        result = execute_bill_level_service(run, stage, bill_run)
        # @lat: [[pipeline-bill-stage-status-model#not_run: nothing was produced, but nothing failed]]
        if result == :skipped_no_pdf
          record_stage_result(bill_run, stage, "skipped", error: "no_pdf_uploaded")
        elsif result == GenerateBillSummaryJob::STOOD_DOWN
          record_stage_result(bill_run, stage, "skipped", reason: "no_model_call_made")
        elsif result == GenerateBillSummaryJob::NOT_RUN
          record_stage_result(bill_run, stage, "not_run", reason: "nothing_was_produced")
        else
          record_stage_result(bill_run, stage, "succeeded")
        end
        bill_run.mark_succeeded! if bill_run.can_mark_succeeded?
        SwayLogging.info(
          "run_legislation_pipeline.bill_progress",
          run_id: run.id, stage: stage, bill: bill_run.bill_external_id,
          n: processed_count, of: total_bills,
          elapsed_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - bill_started_at) * 1000).round,
          origin: @origin
        )
        consecutive_failures = 0
      rescue BillProcessingError => e
        record_bill_stage_failure(bill_run, stage, e, recovery_label: "bill_processing_error")
        bill_run.mark_failed! if bill_run.can_mark_failed?
        consecutive_failures += 1

        if consecutive_failures >= CONSECUTIVE_FAILURE_BUDGET
          run.update_columns(error_message: "aborted_after_#{CONSECUTIVE_FAILURE_BUDGET}_consecutive_#{stage}_failures")
          PipelineActivityLogger.log_stage_budget_tripped!(
            run: run,
            stage: stage,
            consecutive_failures: consecutive_failures,
            last_failed_bill_run: bill_run
          )
          raise StageError, "stage #{stage} aborted after #{CONSECUTIVE_FAILURE_BUDGET} consecutive failures"
        end
      rescue => e
        # @lat: [[legislation-pipeline#Runs, resume and restart#A stage that produced nothing is not a success]]
        record_bill_stage_failure(bill_run, stage, e, recovery_label: "standard_error")
        raise StageError, "stage #{stage} crashed on bill ##{bill_run.bill_external_id}: #{e.class.name}: #{e.message.to_s[0, 500]}"
      end
    end

    submit_summary_batches!(run, submission) if submission

    SwayLogging.info(
      "run_legislation_pipeline.stage_complete",
      run_id: run.id, stage: stage, processed: processed_count, of: total_bills,
      elapsed_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - stage_started_at) * 1000).round,
      origin: @origin
    )

    # @lat: [[llm-summaries#Batch summarisation#Why a submitted item is a verdict, not a silence]]
    stage_succeeded_count = run.pipeline_run_bills
      .where(
        "json_extract(stage_results, ?) IN (?, ?, ?, ?)",
        "$.#{stage}.status", "succeeded", "skipped", "not_run", "awaiting_batch"
      )
      .count
    raise StageError, "all bills failed in stage #{stage} (stage-local success = 0)" if stage_succeeded_count.zero?

    AWAITING_SUMMARY_BATCH if submission&.batches&.any?
  end

  # @lat: [[llm-summaries#Batch summarisation#Why no job waits on a batch]]
  def submit_summary_batches!(run, submission)
    submission.submit!
    submission.verdicts.each { |verdict| record_batch_verdict(verdict) }
    SwayLogging.info(
      "run_legislation_pipeline.summary_batches_submitted",
      run_id: run.id,
      batches: submission.batches.length,
      items: submission.item_count,
      batch_ids: submission.batches.map(&:batch_id)
    )
  rescue StageError
    raise
  rescue => e
    raise StageError, "summarize: batch submit failed: #{e.class.name}: #{e.message.to_s[0, 500]}"
  end

  # @lat: [[llm-summaries#Batch summarisation#Why a submitted item is a verdict, not a silence]]
  def record_batch_verdict(verdict)
    bill_run = verdict.bill_run
    case verdict.outcome
    when SummaryBatchSubmission::AWAITING_BATCH
      record_stage_result(bill_run, :summarize, "awaiting_batch")
    when SummaryBatchSubmission::NOT_CLAIMED
      # @lat: [[llm-summaries#Batch summarisation#Why a row is claimed before the batch is bought]]
      record_stage_result(bill_run, :summarize, "not_run", reason: "row_owned_by_another_writer")
    else
      record_stage_result(bill_run, :summarize, "skipped", reason: "no_model_call_made")
      bill_run.mark_succeeded! if bill_run.can_mark_succeeded?
    end
  end

  def execute_bill_level_service(run, stage, bill_run)
    case stage
    when :extract_text
      execute_extract_text(bill_run)
    when :summarize
      # @lat: [[pipeline-bill-stage-status-model#Counting stage success]]
      GenerateBillSummaryJob.perform_now(resolve_bill!(bill_run).id)
    else
      klass = STAGE_SERVICES[stage]
      raise StageError, "unknown bill-level stage #{stage}" unless klass

      service_class = klass #: String
      service_class.constantize.new(bill: resolve_bill!(bill_run), bill_run: bill_run, run: run).call
    end
  # @lat: [[run-legislation-pipeline-job-internals#Inside execute_bill_level_service and execute_extract_text#Why only ExtractionFailed is a per-bill failure]]
  rescue MupdfExtractor::ExtractionFailed => e
    raise BillProcessingError, "extract_text: #{e.message.to_s[0, 500]}"
  rescue GenerateBillSummaryJob::BillSummaryError => e
    # @lat: [[run-legislation-pipeline-job-internals#Inside execute_bill_level_service and execute_extract_text#Why a bad LLM response converts to a per-bill failure]]
    raise BillProcessingError, "summarize: #{e.message.to_s[0, 500]}"
  rescue Legislation::Paths::UnsafeExternalIdError => e
    # @lat: [[pipeline-unsafe-external-id-rescue#This one rescue covers every reachable raise]]
    raise BillProcessingError, "#{stage}: #{e.message.to_s[0, 500]}"
  end

  # @lat: [[legislation-pipeline#A skipped extraction does not establish a text prerequisite]]
  def execute_extract_text(bill_run)
    bill = resolve_bill!(bill_run)

    out_path = Legislation::Paths.bill_text_file(bill.external_id, sway_locale: bill.sway_locale&.name)
    pdf_path = locate_pdf(bill)

    if pdf_path
      text = MupdfExtractor.new(pdf_path.to_s).call
      bill.update!(extracted_text: text)
      Legislation::ArtifactWriter.write(out_path, text, stage: "extract_text")
      nil #: Symbol?
    elsif (extracted = bill.extracted_text) && !extracted.empty?
      Legislation::ArtifactWriter.write(out_path, extracted, stage: "extract_text") unless File.exist?(out_path)
      nil #: Symbol?
    elsif File.exist?(out_path) && !(disk_text = File.read(out_path)).strip.empty?
      bill.update!(extracted_text: disk_text)
      nil #: Symbol?
    else
      :skipped_no_pdf
    end
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#How a stage resolves its SwayLocale]]
  def resolve_bill(bill_run)
    run = bill_run.legislation_pipeline_run
    locale_id = run&.effective_sway_locale&.id || run&.sway_locale_id
    Legislation::PipelineBillLookup.find(bill_run.bill_external_id, sway_locale_id: locale_id)
  end

  # @lat: [[run-legislation-pipeline-job-internals#Why resolve_bill! centralizes the nil check for all three dispatch arms]]
  def resolve_bill!(bill_run)
    bill = resolve_bill(bill_run)
    return bill unless bill.nil?

    raise BillProcessingError, "no Bill row for external_id #{bill_run.bill_external_id}"
  end

  # @lat: [[llm-summaries#Batch summarisation#One stage-result writer for the job and the ingest]]
  def record_stage_result(bill_run, stage, status, error: nil, reason: nil)
    PipelineStageResult.record(
      bill_run: bill_run, stage: stage, status: status, error: error, reason: reason
    )
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart#A stage that produced nothing is not a success]]
  def record_bill_stage_failure(bill_run, stage, exception, recovery_label: nil)
    error_detail = exception.is_a?(BillProcessingError) ? exception.message.to_s[0, 500] : "#{exception.class.name}: #{exception.message.to_s[0, 500]}"
    recovery = recovery_label || (exception.is_a?(BillProcessingError) ? "bill_processing_error" : "standard_error")

    bill_run.update_columns(error_message: exception.message.to_s.truncate(500))
    begin
      record_stage_result(bill_run, stage, "failed", error: error_detail)
    rescue ArgumentError => arg_e
      SwayLogging.log_exception(
        "orchestrator.record_stage_result_invalid_stage",
        exception: arg_e,
        stage: stage,
        recovery: recovery
      )
    end
  end

  # @lat: [[pipeline-bill-stage-status-model#not_run: nothing was produced, but nothing failed]]
  def stage_already_succeeded?(bill_run, stage)
    status = (bill_run.stage_results || {}).dig(stage.to_s, "status")
    status == "succeeded" || status == "skipped"
  end

  # @lat: [[run-legislation-pipeline-job-internals#Why locate_pdf calls the non-raising resolve_bill]]
  def locate_pdf(bill)
    Pathname.glob(Legislation::Paths.bill_pdf_glob(bill.external_id, sway_locale: bill.sway_locale&.name)).first
  end

  # @lat: [[run-legislation-pipeline-job-internals#Inside run_bill_level_stage#Why the environment is preflighted before the per-bill loop]]
  def preflight_stage_environment!(stage)
    return unless stage == :extract_text

    begin
      MupdfExtractor.preflight!
    rescue MupdfExtractor::MissingTessdataError => e
      raise StageError, "TESSDATA_PREFIX not set: #{e.message.to_s[0, 300]}"
    end
  end

  # @lat: [[llm-summaries#Batch summarisation#One finalizer for the job and the ingest]]
  def finalize_run_terminal_state(run)
    PipelineRunFinalizer.call(run: run, origin: @origin)
  end

  def handle_run_failure(run, error)
    return if run.nil?

    run.update_columns(error_message: error.message.to_s.truncate(500))
    # @lat: [[pipeline-run-failure-handling#Why OperatorAbortError bypasses handle_run_failure entirely]]
    if run.can_mark_failed?
      run.mark_failed!
    elsif run.can_force_fail?
      run.force_fail!
    else
      SwayLogging.warn(
        "[RunLegislationPipelineJob] handle_run_failure: run ##{run.id} already in terminal state #{run.status.inspect}; no transition applied"
      )
    end

    # @lat: [[pipeline-run-failure-handling#Why OperatorAbortError bypasses handle_run_failure entirely]]
    PipelineActivityLogger.log_stage_failed!(
      run: run,
      stage_name: run.current_stage.presence || "unknown",
      error_message: error.message.to_s
    )

    SwayLogging.error("run_legislation_pipeline.failed", run_id: run.id, message: error.message)
  rescue ActiveRecord::ActiveRecordError => e
    # @lat: [[pipeline-run-failure-handling#Why OperatorAbortError bypasses handle_run_failure entirely]]
    SwayLogging.error("[RunLegislationPipelineJob] failure handler AR error (re-raise suppressed): #{e.class}: #{e.message}")
  rescue => secondary
    # @lat: [[pipeline-run-failure-handling#Preserving the original error through a secondary failure]]
    SwayLogging.error(
      "[RunLegislationPipelineJob] handle_run_failure SECONDARY failure (re-raise suppressed): " \
      "original=#{error.class}/#{error.message.to_s[0, 200]} | " \
      "secondary=#{secondary.class}/#{secondary.message.to_s[0, 200]}"
    )
  end
end
