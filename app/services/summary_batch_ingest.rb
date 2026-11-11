# frozen_string_literal: true

# @lat: [[llm-summaries#Batch summarisation#A batch is read back exactly once]]
class SummaryBatchIngest
  ENDED = "ended"

  # @lat: [[llm-summaries#Batch summarisation#A batch is read back exactly once]]
  READ_BACK_PROMPT = Llm::PromptPayload.new(system_prompt: "", user_message: "")

  SUMMARY_FAILED_PREFIX = "summary call failed: "
  POSITIONS_FAILED_PREFIX = "positions call failed: "
  POSITIONS_FAILED_WITH_SUMMARY_PREFIX = "positions call failed (the summary is valid): "

  Answer = Data.define(:bill, :provisioning, :answer_type, :custom_id)
  Landed = Data.define(:answer, :outcome)
  Failure = Data.define(:answer, :error)

  def self.call(run:) = new(run: run).call

  def initialize(run:)
    @run = run
    @bill_runs = nil #: Hash[String, PipelineRunBill]?
  end

  def call
    # @lat: [[bill-session-archiving#Bill session archiving#Pipeline and archive exclusion]]
    PipelineLocaleLock.with_locale(run.effective_sway_locale&.id || run.sway_locale_id) do
      run.pending_summary_batches.each { |batch| ingest(batch) }
      finish_run!
    end
  end

  private

  attr_reader :run

  def ingest(batch)
    batch_model = batch_claude_model(batch)
    answers = answers_for(batch)
    begin
      status = Llm::ClaudeBatchService.status(batch_id: batch.batch_id)
      return unless status.processing_status.to_s == ENDED

      results = Llm::ClaudeBatchService.results(
        batch_id: batch.batch_id, items_by_custom_id: items_map(answers, model: batch_model)
      )
    rescue => e
      settle_unreadable(batch, answers, e)
      return
    end

    settle_read(batch, answers, status, results)
  end

  # @lat: [[llm-summaries#Batch summarisation#A batch is read back exactly once]]
  def answers_for(batch)
    BillLlmProvisioning.joins(:bill).where(summary_batch_id: batch.batch_id).includes(:bill).flat_map { |provisioning|
      bill = provisioning.bill

      SummaryBatchItem::ANSWER_TYPES.map do |answer_type|
        Answer.new(
          bill: bill, provisioning: provisioning, answer_type: answer_type,
          custom_id: SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: answer_type)
        )
      end
    }
  end

  # @lat: [[llm-summaries#Batch summarisation#A batch is read back exactly once]]
  def items_map(answers, model: batch_claude_model)
    answers.each_with_object({}) do |answer, out|
      out[answer.custom_id] = Llm::ClaudeBatchService::Item.new(
        custom_id: answer.custom_id,
        prompt: READ_BACK_PROMPT,
        model: model,
        schema: SummaryBatchItem::SCHEMA_HASHES.fetch(answer.answer_type),
        validation_schema: SummaryBatchItem.validation_schema(answer.answer_type)
      )
    end
  end

  def settle_read(batch, answers, status, results)
    by_custom_id = answers.index_by(&:custom_id)
    landed = [] #: Array[Landed]
    failures = [] #: Array[Failure]

    results.each_value do |result|
      answer = by_custom_id[result.custom_id]
      # @lat: [[llm-summaries#Batch summarisation#Why an unknown custom_id is an error, not an exception]]
      next log_unknown_custom_id(batch, result) if answer.nil?

      if result.error
        failures << Failure.new(answer: answer, error: result.error)
        next
      end

      record_batch_usage(result, batch: batch)

      begin
        landed << Landed.new(answer: answer, outcome: persist(batch, answer, result))
      rescue => e
        SwayLogging.log_exception(
          "summary_batch_ingest.persist_failed",
          exception: e, run_id: run.id, batch_id: batch.batch_id,
          bill_id: answer.bill.id, answer_type: answer.answer_type,
          message: "this answer could not be written, so it settles as a failure and the rest of " \
            "the batch still lands"
        )
        failures << Failure.new(answer: answer, error: e)
      end
    end

    settle(batch, landed: landed, failures: failures, counts: counts_from(status, results))
  end

  # @lat: [[llm-summaries#Batch summarisation#What a batch that cannot be read back settles as]]
  def settle_unreadable(batch, answers, error)
    if batch.live?
      SwayLogging.warn(
        "summary_batch_ingest.read_failed",
        run_id: run.id, batch_id: batch.batch_id,
        error_class: error.class.name, message: error.message.to_s[0, 300]
      )
      return
    end

    SwayLogging.warn(
      "summary_batch_ingest.expired_unread",
      run_id: run.id, batch_id: batch.batch_id,
      item_count: batch.item_count,
      error_class: error.class.name, message: error.message.to_s[0, 300]
    )
    landed = [] #: Array[Landed]
    failures = [] #: Array[Failure]
    answers.each do |answer|
      if outstanding?(answer)
        failures << Failure.new(answer: answer, error: error)
      else
        landed << Landed.new(answer: answer, outcome: :superseded)
      end
    end
    settle(batch, landed: landed, failures: failures, counts: expired_counts(batch, failures))
  end

  # @lat: [[llm-summaries#Batch summarisation#What a batch that cannot be read back settles as]]
  def outstanding?(answer)
    if answer.answer_type == SummaryBatchItem::POSITIONS
      answer.provisioning.positions_owed?
    else
      answer.provisioning.llm_summary.blank?
    end
  end

  # @lat: [[llm-summaries#Batch summarisation#A retry asks eligibility again before it buys]]
  def retryable_answer?(answer)
    eligibility = SummaryItemEligibility.for(bill: answer.bill, provisioning: answer.provisioning)
    return false if eligibility.operator_paste?

    if answer.answer_type == SummaryBatchItem::POSITIONS
      answer.provisioning.positions_owed?
    else
      answer.provisioning.llm_summary.blank? && eligibility.summary?
    end
  end

  def persist(batch, answer, result)
    SummaryBatchResultPersister.call(
      bill: answer.bill, provisioning: answer.provisioning, answer_type: answer.answer_type,
      result: result, batch_id: batch.batch_id, active_categories: active_categories
    )
  end

  # @lat: [[llm-summaries#Batch summarisation#The read is recorded before the retry is bought]]
  def settle(batch, landed:, failures:, counts:)
    mark_ingested!(batch, counts)

    # @lat: [[llm-summaries#Batch summarisation#A failed item is retried once, as a batch]]
    retried = retry_failures(batch, failures)

    state = {} #: Hash[Integer, SummaryBatchIngest::entry]
    landed.each { |entry| entry_for(state, entry.answer)[:landed] << entry }
    failures.each do |failure|
      entry = entry_for(state, failure.answer)
      retried.include?(failure.answer.custom_id) ? (entry[:retried] = true) : (entry[:failed] << failure)
    end

    state.each_value do |entry|
      settle_bill(entry)
    rescue => e
      SwayLogging.log_exception(
        "summary_batch_ingest.bill_not_settled",
        exception: e, run_id: run.id, batch_id: batch.batch_id, bill_id: entry[:bill].id,
        message: "this bill's row was left for the reclaim sweep, and the rest of the batch " \
          "still settled"
      )
    end
  end

  def entry_for(state, answer)
    state[answer.provisioning.id] ||= {
      bill: answer.bill, provisioning: answer.provisioning,
      landed: [], failed: [], retried: false
    }
  end

  # @lat: [[llm-summaries#Batch summarisation#What settles a bill once its items are accounted for]]
  def settle_bill(entry)
    return if entry[:retried]

    landed = entry[:landed]
    failed = entry[:failed]
    return if landed.empty? && failed.empty?

    bill = entry[:bill]
    if landed.any? { |item| item.outcome == :vanished }
      record_stage(bill, "not_run", reason: "row_gone_before_the_answer_landed")
      return
    end

    provisioning = entry[:provisioning]
    report_failures(bill, failed)

    if landed.any?
      settle_bill_completed(bill, provisioning, landed, failed)
    else
      settle_bill_failed(bill, provisioning, failed)
    end
  end

  def settle_bill_completed(bill, provisioning, landed, failed)
    write_partial_failure!(provisioning, failed) if failed.any?
    SummaryRunSettle.completed!(
      bill, provisioning,
      clear_generation_error: failed.empty? && landed.all? { |item| item.outcome == :superseded },
      recompute_score: true
    )
    record_stage(bill, "succeeded")
  end

  def settle_bill_failed(bill, provisioning, failed)
    message = failure_text(provisioning, failed)
    # @lat: [[llm-summaries#Batch summarisation#What settles a bill once its items are accounted for]]
    return settle_half_written(bill, provisioning, failed) if half_written?(provisioning)

    case settle_failed!(provisioning, message)
    when :operator_paste then record_stage(bill, "succeeded")
    when :row_moved then record_stage(bill, "not_run", reason: "row_moved_before_the_failure_settled")
    else record_stage(bill, "failed", error: message)
    end
  end

  def half_written?(provisioning)
    provisioning.llm_summary.present? || provisioning.draft_org_positions.present?
  end

  def settle_half_written(bill, provisioning, failed)
    write_partial_failure!(provisioning, failed)
    SummaryRunSettle.completed!(
      bill, provisioning, clear_generation_error: false, recompute_score: true
    )
    record_stage(bill, "succeeded")
  end

  def record_stage(bill, status, error: nil, reason: nil)
    bill_run = bill_run_for(bill)
    if bill_run.nil?
      SwayLogging.warn(
        "summary_batch_ingest.no_bill_run",
        run_id: run.id, bill_id: bill.id, external_id: bill.external_id,
        message: "this run has no pipeline_run_bills row for the bill, so the summarize stage " \
          "result could not be recorded against it"
      )
      return
    end

    PipelineStageResult.record(
      bill_run: bill_run, stage: :summarize, status: status, error: error, reason: reason
    )
    case status
    when "succeeded" then bill_run.mark_succeeded! if bill_run.can_mark_succeeded?
    when "failed" then bill_run.mark_failed! if bill_run.can_mark_failed?
    end
  end

  def failure_text(provisioning, failures)
    summary_present = provisioning.llm_summary.present?
    text = failures.map { |failure|
      reason = Sway::Utf8.scrub(failure.error.message.to_s)
      "#{failure_prefix(failure, summary_present)}#{reason}"
    }.join(" ")
    text[0, GenerateBillSummaryJob::MAX_GENERATION_ERROR_LENGTH].to_s
  end

  def failure_prefix(failure, summary_present)
    return SUMMARY_FAILED_PREFIX unless failure.answer.answer_type == SummaryBatchItem::POSITIONS

    summary_present ? POSITIONS_FAILED_WITH_SUMMARY_PREFIX : POSITIONS_FAILED_PREFIX
  end

  def write_partial_failure!(provisioning, failures)
    message = failure_text(provisioning, failures)
    SummaryRunLock.settle_under_lock(provisioning) do
      unless SummaryRunMarker.operator_paste?(provisioning.summary_run_id)
        provisioning.update_columns(generation_error: message)
      end
    end
  end

  def settle_failed!(provisioning, message)
    SummaryRunLock.settle_under_lock(provisioning) do
      next :operator_paste if SummaryRunMarker.operator_paste?(provisioning.summary_run_id)
      next :row_moved unless provisioning.generating?

      provisioning.update_columns(generation_error: message)
      provisioning.mark_failed!
      :failed
    end
  end

  # @lat: [[llm-summaries#Batch summarisation#A failed item is retried once, as a batch]]
  def report_failures(bill, failures)
    failures.each do |failure|
      message = Sway::Utf8.scrub(failure.error.message.to_s)
      if failure.error.is_a?(Llm::SchemaError)
        PipelineActivityLogger.log_llm_json_parse_failure!(
          bill: bill, error_message: message, raw_excerpt: message
        )
      else
        PipelineActivityLogger.log_llm_provider_error!(bill: bill, error_message: message)
      end
    rescue => e
      SwayLogging.warn(
        "summary_batch_ingest.activity_log_write_failed",
        bill_id: bill.id, error_class: e.class.name, message: e.message.to_s[0, 300]
      )
    end
  end

  # @lat: [[llm-summaries#Batch summarisation#A failed item is retried once, as a batch]]
  def retry_failures(batch, failures)
    retried = Set.new #: Set[String]
    return retried if failures.empty?
    return retried unless batch.retryable?

    retry_model = batch_claude_model(batch)
    items = [] #: Array[Llm::ClaudeBatchService::Item]
    retryable = [] #: Array[Failure]
    failures.each do |failure|
      next unless retryable_answer?(failure.answer)

      items << SummaryBatchItem.build(
        bill: failure.answer.bill, answer_type: failure.answer.answer_type,
        model: retry_model, active_categories: active_categories
      )
      retryable << failure
    rescue => e
      SwayLogging.warn(
        "summary_batch_ingest.retry_item_not_rebuilt",
        run_id: run.id, batch_id: batch.batch_id, bill_id: failure.answer.bill.id,
        answer_type: failure.answer.answer_type,
        error_class: e.class.name, message: e.message.to_s[0, 300]
      )
    end
    return retried if items.empty?

    record = submit_retry!(batch, items, model: retry_model)
    restamped = retryable.uniq { |failure| failure.answer.provisioning.id }
      .select { |failure| restamp!(failure.answer, record) }
      .map { |failure| failure.answer.provisioning.id }
      .to_set
    retryable.each do |failure|
      retried << failure.answer.custom_id if restamped.include?(failure.answer.provisioning.id)
    end
    retried
  rescue => e
    SwayLogging.log_exception(
      "summary_batch_ingest.retry_failed",
      exception: e, run_id: run.id, batch_id: batch.batch_id,
      message: "the items this retry would have carried settle failed; if the submit itself " \
        "succeeded, the retry_bought line above names the batch nothing now records"
    )
    Set.new
  end

  def submit_retry!(batch, items, model: nil)
    submitted = Llm::ClaudeBatchService.submit(items: items)
    # @lat: [[llm-summaries#Batch summarisation#A bought batch is logged before it is recorded]]
    SwayLogging.info(
      "summary_batch_ingest.retry_bought",
      run_id: run.id, from_batch_id: batch.batch_id, batch_id: submitted.id, items: items.length
    )
    record = run.pipeline_run_summary_batches.create!(
      batch_id: submitted.id,
      submitted_at: Time.current,
      expires_at: submitted.expires_at,
      attempt: batch.attempt + 1,
      item_count: items.length,
      model: model || batch_claude_model(batch)
    )
    SwayLogging.info(
      "summary_batch_ingest.retry_submitted",
      run_id: run.id, from_batch_id: batch.batch_id, batch_id: record.batch_id,
      attempt: record.attempt, items: items.length
    )
    record
  end

  # @lat: [[llm-summaries#Batch summarisation#A failed item is retried once, as a batch]]
  def restamp!(answer, record)
    provisioning = answer.provisioning
    SummaryRunLock.settle_under_lock(provisioning) do
      next false if SummaryRunMarker.operator_paste?(provisioning.summary_run_id)

      provisioning.update_columns(
        summary_run_id: SummaryRunMarker.run_claim(
          SummaryRunMarker.batch_run_id(batch_id: record.batch_id, bill_id: answer.bill.id)
        ),
        summary_batch_id: record.batch_id,
        summary_batch_expires_at: record.expires_at,
        summary_batch_testimony_digest: provisioning.testimony_digest,
        updated_at: Time.current
      )
      true
    end
  end

  # @lat: [[llm-summaries#Batch summarisation#A batch is read back exactly once]]
  def mark_ingested!(batch, counts)
    batch.update_columns(
      ingested_at: Time.current,
      succeeded_count: counts.fetch(:succeeded),
      errored_count: counts.fetch(:errored),
      canceled_count: counts.fetch(:canceled),
      expired_count: counts.fetch(:expired),
      updated_at: Time.current
    )
  end

  # @lat: [[llm-summaries#Batch summarisation#Where the per-outcome counts come from]]
  def counts_from(status, results)
    usable = results.each_value.count { |result| result.error.nil? }
    request_counts = status.respond_to?(:request_counts) ? status.request_counts : nil
    return {succeeded: usable, errored: results.size - usable, canceled: 0, expired: 0} if request_counts.nil?

    unusable = [count_of(request_counts, :succeeded) - usable, 0].max
    {
      succeeded: usable,
      errored: count_of(request_counts, :errored) + unusable,
      canceled: count_of(request_counts, :canceled),
      expired: count_of(request_counts, :expired)
    }
  end

  def count_of(request_counts, name)
    request_counts.respond_to?(name) ? request_counts.public_send(name).to_i : 0
  end

  def expired_counts(batch, failures)
    expired = batch.item_count.positive? ? batch.item_count : failures.length
    {succeeded: 0, errored: 0, canceled: 0, expired: expired}
  end

  def log_unknown_custom_id(batch, result)
    SwayLogging.warn(
      "summary_batch_ingest.unknown_custom_id",
      run_id: run.id, batch_id: batch.batch_id, custom_id: result.custom_id,
      message: "no bill row answers this custom_id any more, so nothing can be written for it " \
        "and nothing can be retried"
    )
    nil
  end

  # @lat: [[llm-summaries#Batch summarisation#Why the waiting state loops back to summarizing]]
  def finish_run!
    return if run.pipeline_run_summary_batches.pending_ingest.exists?

    run.resume_summary_batch! if run.can_resume_summary_batch?
    run.complete_summarize! if run.can_complete_summarize?
    PipelineRunFinalizer.call(run: run)
    SwayLogging.info("summary_batch_ingest.run_finished", run_id: run.id, status: run.status)
  end

  def bill_run_for(bill)
    bill_runs[bill.external_id.to_s]
  end

  def bill_runs
    @bill_runs ||= run.pipeline_run_bills.index_by { |bill_run| bill_run.bill_external_id.to_s }
  end

  def record_batch_usage(result, batch: nil)
    return unless result.respond_to?(:usage)

    usage = result.usage
    return if usage.nil?

    model_name = if result.respond_to?(:model) && result.model.present?
      result.model
    elsif batch&.respond_to?(:model) && batch.model.present?
      batch.model
    else
      batch_claude_model(batch)
    end

    metadata = {
      model: model_name,
      input_tokens: usage.input_tokens.to_i,
      output_tokens: usage.output_tokens.to_i
    }

    if usage.respond_to?(:cache_creation_input_tokens) && usage.cache_creation_input_tokens
      metadata[:cache_creation_input_tokens] = usage.cache_creation_input_tokens.to_i
    end
    if usage.respond_to?(:cache_read_input_tokens) && usage.cache_read_input_tokens
      metadata[:cache_read_input_tokens] = usage.cache_read_input_tokens.to_i
    end

    SwayLogging.info("claude.usage.recorded.batch", **metadata)
  end

  def batch_claude_model(batch = nil)
    if batch&.respond_to?(:model) && batch.model.present?
      route = Llm::ModelCatalog.lookup(batch.model)
      return route.api_model if route&.claude?
    end

    standing_route = begin
      Llm::RouteResolver.resolve(purpose: :summary)
    rescue Llm::UnknownRouteError
      nil
    end
    return standing_route.api_model if standing_route&.claude?

    Llm::ModelCatalog.active_claude_choices.first
  end

  def model(batch = nil) = batch_claude_model(batch)

  def active_categories = @active_categories ||= Category.where(active: true).order(:name).to_a
end
