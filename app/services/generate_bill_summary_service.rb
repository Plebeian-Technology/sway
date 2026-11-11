# frozen_string_literal: true

# @lat: [[generate-bill-summary-service-overview#What regenerate: changes]]
# @lat: [[generate-bill-summary-service-outcomes#GenerateBillSummaryService.call return values]]
class GenerateBillSummaryService
  # @lat: [[bill-llm-run-reclaim-timing#Both stuck states, not just one]]
  RECLAIM_ABANDONED_AFTER = 1.hour

  # @lat: [[unqueued-row-release-message#The four shapes that reach this message]]
  UNQUEUED_ERROR =
    "Sway could not start this summary run. Nothing was charged, and anything you typed was " \
    "saved. Try again."

  MAX_SUMMARY_INSTRUCTIONS_LENGTH = 2000

  # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
  def initialize(bill:, actor:, regenerate: false, supplemental_testimony: nil,
    clear_supplemental_testimony: false, summarization_model: nil, summary_instructions: nil,
    reasoning_effort: nil)
    @bill = bill
    @actor = actor
    @regenerate = regenerate
    @summarization_model = summarization_model.is_a?(::String) ? summarization_model.strip.presence : nil
    raw_effort = reasoning_effort.is_a?(::String) ? reasoning_effort.strip.presence : nil
    @reasoning_effort = raw_effort&.casecmp("default")&.zero? ? "default" : raw_effort
    # @lat: [[generate-bill-summary-service-concurrency#initialize: why only a String is accepted as testimony]]
    @supplemental_testimony = supplemental_testimony.is_a?(::String) ? supplemental_testimony : nil
    @clear_supplemental_testimony = clear_supplemental_testimony
    @invalid_summary_instructions = false
    @summary_instructions = normalize_summary_instructions(summary_instructions)
  end

  def call
    return :invalid_summary_instructions if @invalid_summary_instructions

    # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    if @summarization_model && !AdminSetting.offered_models.include?(@summarization_model)
      return :unsupported_model
    end

    # @lat: [[generate-bill-summary-service-outcomes#GenerateBillSummaryService.call return values]]
    if @reasoning_effort
      target_model = @summarization_model.presence || AdminSetting.singleton.summarization_model
      valid_effort = @reasoning_effort == "default" || AdminSetting::REASONING_EFFORTS.include?(@reasoning_effort)
      if !valid_effort || !Llm::ModelCatalog.supports_reasoning?(target_model)
        return :unsupported_reasoning_effort
      end
    end

    # @lat: [[bill-summary-call-preconditions#Why GenerateBillSummaryService.call gates on runnable?, not just source material]]
    return :no_pipeline_data unless runnable?

    # @lat: [[generate-bill-summary-service-concurrency#Why the provisioning row is created after the runnable? guard]]
    provisioning = @bill.bill_llm_provisioning || @bill.create_bill_llm_provisioning!

    # @lat: [[generate-bill-summary-service-concurrency#Why first_generation is captured before the lock touches the row]]
    first_generation = provisioning.llm_summary.blank?

    # @lat: [[generate-bill-summary-service-concurrency#Why first_generation is captured before the lock touches the row]]
    # @type var marker_before_arm: String?
    marker_before_arm = nil

    # @lat: [[generate-bill-summary-service-concurrency#Why summary_run_id and generation_error are cleared before enqueue!]]
    result = provisioning.with_lock do
      # @lat: [[generate-bill-summary-service-concurrency#Why summary_run_id and generation_error are cleared before enqueue!]]
      reclaim_abandoned_run!(provisioning)

      next :already_in_progress if provisioning.pending? || provisioning.generating?

      # @lat: [[generate-bill-summary-service-concurrency#Why summary_run_id and generation_error are cleared before enqueue!]]
      log_operator_paste_superseded(provisioning)

      # @lat: [[generate-bill-summary-service-concurrency#Why summary_run_id and generation_error are cleared before enqueue!]]
      marker_before_arm = provisioning.summary_run_id

      # @lat: [[generate-bill-summary-service-concurrency#Why summary_run_id and generation_error are cleared before enqueue!#The Steep typing trap on the attrs hash literal]]
      # @type var attrs: Hash[Symbol, String?]
      attrs = {summary_run_id: nil, generation_error: nil}
      provisioning.update!(attrs.merge(supplemental_testimony_attrs(provisioning)))

      provisioning.enqueue!
      :enqueued
    end
    return result unless result == :enqueued

    # @lat: [[generate-bill-summary-service-concurrency#Why the enqueue and the audit log run after the lock commits]]
    begin
      job_kwargs = {}
      job_kwargs[:summarization_model] = @summarization_model if @summarization_model
      job_kwargs[:summary_instructions] = @summary_instructions if @summary_instructions
      job_kwargs[:reasoning_effort] = @reasoning_effort if @reasoning_effort

      if job_kwargs.any?
        GenerateBillSummaryJob.perform_later(@bill.id, **job_kwargs)
      else
        GenerateBillSummaryJob.perform_later(@bill.id)
      end
    rescue => e
      release_unqueued_row!(provisioning, e, restore_marker: marker_before_arm)
      return :enqueue_failed
    end
    # @lat: [[generate-bill-summary-service-concurrency#Why the audit log is unconditional, not only for regenerate]]
    PipelineActivityLogger.log_summary_regenerate_triggered!(
      bill: @bill, actor: @actor, first_generation: first_generation
    )

    :enqueued
  end

  private

  def normalize_summary_instructions(value)
    return nil if value.nil?

    unless value.is_a?(::String)
      @invalid_summary_instructions = true
      return nil
    end

    trimmed = value.sub(/\A[ \t\r\n\f\v]+/, "").sub(/[ \t\r\n\f\v]+\z/, "")
    if trimmed.length > MAX_SUMMARY_INSTRUCTIONS_LENGTH
      @invalid_summary_instructions = true
      return nil
    end

    trimmed.empty? ? nil : trimmed
  end

  # @lat: [[generate-bill-summary-service-concurrency#release_unqueued_row!: putting the row back where the arm found it]]
  def release_unqueued_row!(provisioning, error, restore_marker: nil)
    SwayLogging.log_exception(
      "generate_bill_summary_service.enqueue_failed",
      exception: error,
      bill_id: @bill.id,
      provisioning_id: provisioning.id,
      message: "the row was armed and the job could not be queued — releasing the row so the " \
        "operator's next click is not refused by a run that will never happen"
    )

    provisioning.with_lock do
      next unless provisioning.pending?

      if SummaryRunMarker.operator_paste?(restore_marker) && provisioning.summary_run_id.nil?
        provisioning.update_columns(summary_run_id: restore_marker)
      end
      # @lat: [[generate-bill-summary-service-concurrency#release_unqueued_row!: putting the row back where the arm found it#Why the reason goes on the row, not only in the log]]
      provisioning.update_columns(
        generation_error: UNQUEUED_ERROR[0, GenerateBillSummaryJob::MAX_GENERATION_ERROR_LENGTH]
      )
      provisioning.mark_skipped!
    end
  rescue => e
    SwayLogging.warn(
      "generate_bill_summary_service.release_failed",
      bill_id: @bill.id,
      provisioning_id: provisioning.id,
      error_class: e.class.name,
      message: e.message.to_s[0, 300]
    )
  end

  # @lat: [[generate-bill-summary-service-concurrency#log_operator_paste_superseded: why it logs before the erasing write]]
  def log_operator_paste_superseded(provisioning)
    return unless SummaryRunMarker.operator_paste?(provisioning.summary_run_id)

    SwayLogging.warn(
      "generate_bill_summary_service.superseding_operator_paste",
      bill_id: @bill.id,
      provisioning_id: provisioning.id,
      regenerate: @regenerate,
      message: "this row's summary was pasted by an operator — the requested generation will " \
        "replace it, which is the only route that overrides a paste"
    )
  end

  # @lat: [[bill-llm-run-reclaim-timing#Both stuck states, not just one]]
  # @lat: [[abandoned-run-reclaim#Why ReclaimAbandonedSummaryRunsJob exists]]
  def reclaim_abandoned_run!(provisioning)
    # @lat: [[generate-bill-summary-service-concurrency#reclaim_abandoned_run!: why it reads BillLlmProvisioning.reclaimable?]]
    return unless provisioning.reclaimable?

    SwayLogging.warn(
      "generate_bill_summary_service.reclaimed_abandoned_run",
      bill_id: @bill.id,
      provisioning_id: provisioning.id,
      generation_status: provisioning.generation_status,
      abandoned_since: provisioning.updated_at,
      reclaim_after_seconds: RECLAIM_ABANDONED_AFTER.to_i,
      message: "no writer touched this row for longer than the job's worst-case wall clock — " \
        "reclaiming it so the operator's trigger is not blocked forever"
    )

    SummaryRunRelease.call(provisioning, rearmed_by_caller: true)
  end

  # @lat: [[bill-summary-call-preconditions#Why GenerateBillSummaryService.call gates on runnable?, not just source material]]
  def runnable?
    return true if BillSummaryPromptBuilder.new(@bill).source_present?
    return true if @supplemental_testimony.present?
    return true if @bill.bill_llm_provisioning&.testimony_present?
    return true if NewsArticleTestimonyService.commentary_eligible?(@bill)

    NewsOrgPositionGroundingService.reporting_eligible?(@bill)
  end

  # @lat: [[supplemental-testimony-write-rule#Why blank never clears]]
  def supplemental_testimony_attrs(provisioning)
    SupplementalTestimonyWrite.attrs(
      value: @supplemental_testimony,
      clear: @clear_supplemental_testimony,
      provisioning: provisioning
    )
  end
end
