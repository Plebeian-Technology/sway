# frozen_string_literal: true

# @lat: [[llm-summaries#Batch summarisation#What identity a batch result writes as its receipt]]
class SummaryBatchResultPersister
  PROVIDER_LABEL = "claude"

  def self.call(bill:, provisioning:, answer_type:, result:, batch_id:, active_categories: nil)
    new(
      bill: bill, provisioning: provisioning, answer_type: answer_type,
      result: result, batch_id: batch_id, active_categories: active_categories
    ).call
  end

  def initialize(bill:, provisioning:, answer_type:, result:, batch_id:, active_categories: nil)
    @bill = bill
    @provisioning = provisioning
    @answer_type = answer_type
    @result = result
    @batch_id = batch_id
    @active_categories = active_categories
  end

  def call
    outcome = (answer_type == SummaryBatchItem::POSITIONS) ? persist_positions : persist_summary
    report(outcome)
    outcome
  end

  private

  attr_reader :bill, :provisioning, :answer_type, :result, :batch_id

  # @lat: [[llm-summaries#Batch summarisation#What identity a batch result writes as its receipt]]
  def receipt = SummaryRunMarker.batch_run_id(batch_id: batch_id, bill_id: bill.id)

  def pending_receipt
    batch_record = PipelineRunSummaryBatch.find_by(batch_id: batch_id)
    return nil unless batch_record

    SummaryRunMarker.batch_pending_id(
      run_id: batch_record.legislation_pipeline_run_id,
      bill_id: bill.id
    )
  end

  def resolve_snapshot(target_answer_type)
    scope = (target_answer_type == SummaryBatchItem::POSITIONS) ? bill.news_article_source_snapshots.for_testimony : bill.news_article_source_snapshots.for_summary

    snapshot = scope.find_by(run_receipt: receipt)
    return snapshot if snapshot

    pending = pending_receipt
    if pending
      snapshot = scope.find_by(run_receipt: pending)
      return snapshot if snapshot
    end

    target_custom_id = SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: target_answer_type)
    snapshot = scope.where(run_receipt: target_custom_id).recent_first.first
    return snapshot if snapshot

    if result.respond_to?(:custom_id) && result.custom_id.present?
      snapshot = scope.where(run_receipt: result.custom_id).recent_first.first
      return snapshot if snapshot
    end

    scope.recent_first.first
  end

  def value = result.value

  def active_categories
    @active_categories ||= Category.where(active: true).order(:name).to_a
  end

  def persist_summary
    snapshot = resolve_snapshot(SummaryBatchItem::SUMMARY)

    manifest_result = NewsSummaryManifestValidator.call(
      bill: bill,
      summary_markdown: value["summary_markdown"],
      news_usage: value["news_usage"],
      source_uses: value["source_uses"],
      snapshot: snapshot
    )

    grounding_result = nil
    if manifest_result.valid?
      if snapshot && manifest_result.news_usage == "cited"
        if value["source_uses"].is_a?(Array) && value["source_uses"].any?
          NewsArticleSourceUse.transaction do
            value["source_uses"].each do |use_payload|
              bna_id = use_payload["bill_news_article_id"]&.to_i
              tv_id = use_payload["text_version_id"]&.to_i
              claim_text = use_payload["claim_text"].to_s
              excerpt = (use_payload["evidence_excerpt"] || use_payload["verbatim_excerpt"]).to_s
              citation_url = use_payload["citation_url"].to_s

              snapshot.source_uses.create!(
                bill_news_article_id: bna_id,
                text_version_id: tv_id,
                claim_text: claim_text,
                evidence_excerpt: excerpt,
                citation_url: citation_url,
                grounding_status: "pending"
              )
            end
          end
        end

        grounding_result = NewsClaimGroundingService.call(
          bill: bill,
          content: value["summary_markdown"],
          snapshot: snapshot,
          news_usage: manifest_result.news_usage,
          persist: true
        )
      end
    else
      grounding_result = manifest_result.structured_refusal
    end

    attrs = SummaryCitationValidator.verdict_attrs(bill: bill, payload: value).merge(
      llm_provider: PROVIDER_LABEL,
      llm_model: result.model,
      llm_summary: value["summary_markdown"],
      llm_full_breakdown: value["full_breakdown_markdown"],
      news_usage: value["news_usage"],
      summary_run_id: receipt,
      llm_generated_at: Time.current
    )
    outcome = SummaryRunPersistGuard.call(
      bill, provisioning, attrs,
      news_source_snapshot: ((value["news_usage"] == "cited") ? snapshot : nil),
      grounding_result: grounding_result
    )
    if outcome == :grounding_refused
      grounding_failure_reason = grounding_result&.errors&.presence&.join("; ") || provisioning.generation_error.presence
      raise Llm::SchemaError, grounding_failure_reason || "News citation manifest failed grounding validation"
    end
    if outcome == :persisted
      BillSummaryPromptSnapshot.forget!(bill: bill)
      assign_categories!
    end
    outcome
  end

  # @lat: [[llm-summaries#Batch summarisation#Why the evidence digest is stamped at submit time]]
  # @lat: [[news-org-position-persistence#Persistence callers]]
  def persist_positions
    testimony_snapshot = resolve_snapshot(SummaryBatchItem::POSITIONS)
    summary_snapshot = resolve_snapshot(SummaryBatchItem::SUMMARY)

    filtered_positions = NewsOrgPositionGroundingService.filter_draft_positions(
      bill: bill,
      raw_positions: value["draft_org_positions"],
      snapshots: [summary_snapshot, testimony_snapshot].compact,
      hearing_testimony_present: provisioning.testimony_present?
    )

    outcome = SummaryRunPersistGuard.call(
      bill, provisioning,
      {
        draft_org_positions: filtered_positions,
        summary_run_id: receipt,
        generation_error: nil
      },
      evidence_digest: provisioning.summary_batch_testimony_digest
    )

    if outcome == :persisted && value["draft_news_testimonies"].present?
      snapshot = testimony_snapshot
      if snapshot
        NewsArticleTestimonyService.persist_drafts!(
          bill: bill,
          payload: value,
          snapshot: snapshot,
          run_receipt: receipt
        )
        NewsArticleTestimonyService.publish_commentary!(
          bill: bill,
          snapshot: snapshot
        )
      end
    end

    outcome
  end

  def assign_categories!
    raw_categories = value["categories"]
    if active_categories.empty?
      SwayLogging.warn(
        "generate_bill_summary.no_active_categories",
        bill_id: bill.id,
        message: "no active categories — skipping category assignment"
      )
    elsif raw_categories.blank?
      SwayLogging.warn(
        "generate_bill_summary.no_categories_in_response",
        bill_id: bill.id,
        message: "LLM response omitted or returned empty categories — completing uncategorized"
      )
    else
      begin
        BillCategoryAssigner.new(bill, raw_categories, active_categories).call
      rescue Llm::SchemaError => e
        SwayLogging.warn(
          "generate_bill_summary.categories_not_matched",
          bill_id: bill.id,
          provisioning_id: provisioning.id,
          raw_categories: raw_categories,
          message: "#{Sway::Utf8.scrub(e.message)} — completing uncategorized; " \
            "BackfillBillCategoriesJob will retry with the constrained categorize prompt"
        )
      end
    end
  end

  def report(outcome)
    case outcome
    when :persisted
      SwayLogging.info(
        "summary_batch_ingest.persisted",
        bill_id: bill.id, provisioning_id: provisioning.id,
        batch_id: batch_id, answer_type: answer_type
      )
    when :superseded then report_superseded
    when :evidence_withdrawn then report_evidence_withdrawn
    when :vanished
      SwayLogging.warn(
        "summary_batch_ingest.row_gone_after_paid_call",
        bill_id: bill.id, provisioning_id: provisioning.id,
        batch_id: batch_id, answer_type: answer_type,
        message: "the provisioning row was deleted while this batch was in flight — the answer " \
          "already paid for has nowhere to land"
      )
    end
  end

  def report_superseded
    SwayLogging.warn(
      "summary_batch_ingest.superseded_by_operator_paste",
      bill_id: bill.id, provisioning_id: provisioning.id,
      batch_id: batch_id, answer_type: answer_type,
      message: "an operator pasted a summary onto this row while the batch was in flight — " \
        "discarding this answer rather than overwriting hand-written work; Regenerate to override"
    )
    PipelineActivityLogger.log_summary_stood_down_for_paste!(bill: bill)
  end

  # @lat: [[llm-summaries#Batch summarisation#Why the evidence digest is stamped at submit time]]
  def report_evidence_withdrawn
    SwayLogging.warn(
      "summary_batch_ingest.positions_evidence_withdrawn",
      bill_id: bill.id, provisioning_id: provisioning.id,
      batch_id: batch_id,
      message: "the testimony changed while the batch was in flight — the new positions were " \
        "discarded and the existing drafts left as they are"
    )
    discarded = GenerateBillSummaryJob::POSITIONS_DISCARDED_PREFIX +
      GenerateBillSummaryJob::POSITIONS_EVIDENCE_WITHDRAWN_REASON
    SummaryRunLock.settle_under_lock(provisioning) do
      unless SummaryRunMarker.operator_paste?(provisioning.summary_run_id)
        provisioning.update_columns(
          generation_error: discarded[0, GenerateBillSummaryJob::MAX_GENERATION_ERROR_LENGTH],
          summary_run_id: receipt
        )
      end
    end
  end
end
