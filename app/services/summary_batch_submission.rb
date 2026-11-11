# frozen_string_literal: true

# @lat: [[llm-summaries#Batch summarisation#Submitting a run's summarisation as chunked batches]]
class SummaryBatchSubmission
  CLAUDE_PROVIDER = "claude"

  AWAITING_BATCH = :awaiting_batch
  SKIPPED = :skipped
  NOT_CLAIMED = :not_claimed

  Candidate = Data.define(:bill_run, :bill, :provisioning, :items)
  Verdict = Data.define(:bill_run, :outcome)

  # @lat: [[llm-summaries#Batch summarisation#Which runs submit a batch at all]]
  # @lat: [[llm-summaries#Batch summarisation#Why the batch path is off until it is switched on]]
  def self.for(run:)
    return nil unless run.bill_id.nil?
    return nil unless AdminSetting.singleton.summary_batch_enabled

    route = begin
      Llm::RouteResolver.resolve(purpose: :summary)
    rescue Llm::UnknownRouteError
      nil
    end
    return nil unless route&.claude?

    new(run: run, route: route)
  end

  def initialize(run:, route: nil)
    @run = run
    @route = route || Llm::RouteResolver.resolve(purpose: :summary)
    unless @route&.claude?
      raise Llm::UnknownRouteError, "summary batch submission requires a Claude route"
    end
    @model = @route.api_model
    @candidates = [] #: Array[Candidate]
    @batches = [] #: Array[PipelineRunSummaryBatch]
    @claimed_provisioning_ids = Set.new #: Set[Integer]
  end

  attr_reader :batches

  # @lat: [[llm-summaries#Batch summarisation#Not every bill earns a batch item]]
  def accumulate(bill_run, bill)
    provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
    eligibility = SummaryItemEligibility.for(bill: bill, provisioning: provisioning)

    items = eligibility.operator_paste? ? [] : build_items(bill, eligibility)

    @candidates << Candidate.new(
      bill_run: bill_run, bill: bill, provisioning: provisioning, items: items
    )
    items.length
  end

  # @lat: [[llm-summaries#Batch summarisation#Why chunking is a progress decision, not a cost one]]
  def submit!
    submittable.each_slice(chunk_size) { |group| submit_chunk(group) }
    batches
  end

  def verdicts
    @candidates.map { |candidate| Verdict.new(bill_run: candidate.bill_run, outcome: outcome_for(candidate)) }
  end

  def item_count = claimed_candidates.sum { |candidate| candidate.items.length }

  private

  attr_reader :run, :model

  def submittable = @candidates.reject { |candidate| candidate.items.empty? }

  def claimed_candidates = @candidates.select { |candidate| claimed?(candidate) }

  def claimed?(candidate) = @claimed_provisioning_ids.include?(candidate.provisioning.id)

  def outcome_for(candidate)
    return SKIPPED if candidate.items.empty?
    return AWAITING_BATCH if claimed?(candidate)

    NOT_CLAIMED
  end

  # @lat: [[llm-summaries#Batch summarisation#Why a row is claimed before the batch is bought]]
  def submit_chunk(group)
    claimed = group.select { |candidate| claim_row!(candidate) }
    return if claimed.empty?

    items = claimed.flat_map(&:items)
    batch = Llm::ClaudeBatchService.submit(items: items)
    # @lat: [[llm-summaries#Batch summarisation#Why the expiry is the server's answer]]
    record = run.pipeline_run_summary_batches.create!(
      batch_id: batch.id,
      model: model,
      submitted_at: Time.current,
      expires_at: batch.expires_at,
      item_count: items.length
    )
    @batches << record

    claimed.each { |candidate| stamp_batch!(candidate, record) }

    SwayLogging.info(
      "summary_batch_submission.chunk_submitted",
      run_id: run.id,
      batch_id: record.batch_id,
      bills: claimed.length,
      items: items.length,
      expires_at: record.expires_at
    )
  end

  # @lat: [[llm-summaries#Batch summarisation#Why a row is claimed before the batch is bought]]
  def claim_row!(candidate)
    outcome = SummaryRunArm.call(
      provisioning: candidate.provisioning,
      job_id: SummaryRunMarker.batch_pending_id(run_id: run.id, bill_id: candidate.bill.id)
    )

    if outcome.armed == true && outcome.decision&.claim_row?
      @claimed_provisioning_ids << candidate.provisioning.id
      return true
    end

    SwayLogging.warn(
      "summary_batch_submission.row_not_claimed",
      run_id: run.id,
      bill_id: candidate.bill.id,
      provisioning_id: candidate.provisioning.id,
      decision: outcome.decision&.name,
      message: "this run may not take the marker on this bill's summary row " \
        "(#{outcome.decision&.name}), so its items were left out of the batch rather than bought " \
        "for an answer that would be discarded"
    )
    false
  end

  # @lat: [[llm-summaries#Batch summarisation#What identity arms a batch-submitted row]]
  def stamp_batch!(candidate, record)
    provisioning = candidate.provisioning
    SummaryRunLock.settle_under_lock(provisioning) do
      unless SummaryRunMarker.operator_paste?(provisioning.summary_run_id)
        provisioning.update_columns(
          summary_run_id: SummaryRunMarker.run_claim(
            SummaryRunMarker.batch_run_id(batch_id: record.batch_id, bill_id: candidate.bill.id)
          ),
          summary_batch_id: record.batch_id,
          summary_batch_expires_at: record.expires_at,
          # @lat: [[llm-summaries#Batch summarisation#Why the evidence digest is stamped at submit time]]
          summary_batch_testimony_digest: provisioning.testimony_digest,
          updated_at: Time.current
        )
      end
    end
  end

  def build_items(bill, eligibility)
    pending_receipt = SummaryRunMarker.batch_pending_id(run_id: run.id, bill_id: bill.id)
    SummaryBatchItem.build_all(
      bill: bill, eligibility: eligibility, model: model, active_categories: active_categories,
      run_receipt: pending_receipt
    )
  end

  # @lat: [[llm-summaries#Batch summarisation#What decides how many batches a run submits]]
  def chunk_size
    @chunk_size ||= begin
      configured = AdminSetting.singleton.summary_batch_chunk_size.to_i
      configured.positive? ? configured : AdminSetting::SUMMARY_BATCH_CHUNK_SIZE_DEFAULT
    end
  end

  def active_categories = @active_categories ||= Category.where(active: true).order(:name).to_a
end
