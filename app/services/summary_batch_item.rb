# frozen_string_literal: true

# @lat: [[llm-summaries#Batch summarisation#What a custom_id has to carry]]
class SummaryBatchItem
  SUMMARY = "summary"
  POSITIONS = "positions"

  ANSWER_TYPES = [SUMMARY, POSITIONS].freeze

  SCHEMA_HASHES = {SUMMARY => BILL_SUMMARY_SCHEMA_HASH, POSITIONS => BILL_POSITIONS_SCHEMA_HASH}.freeze
  VALIDATION_SCHEMAS = {SUMMARY => BILL_SUMMARY_SCHEMA, POSITIONS => BILL_POSITIONS_SCHEMA}.freeze

  # @lat: [[llm-summaries#Batch summarisation#What a custom_id has to carry]]
  def self.custom_id(bill_id:, answer_type:)
    Llm::BatchCustomId.build("bill", bill_id.to_s, answer_type)
  end

  def self.validation_schema(answer_type) = VALIDATION_SCHEMAS.fetch(answer_type)

  # @lat: [[news-org-position-persistence#Persistence callers]]
  def self.build(bill:, answer_type:, model:, active_categories:, run_receipt: nil)
    item_custom_id = custom_id(bill_id: bill.id, answer_type: answer_type)
    receipt_key = run_receipt.presence || item_custom_id
    snapshot = nil
    reporting_snapshot = nil
    if answer_type == SUMMARY
      eligible_news = bill.bill_news_articles.eligible_for_synthesis.order(:id).to_a.select(&:eligible_for_synthesis?)
      if eligible_news.any?
        existing_snapshot = bill.news_article_source_snapshots.for_summary.where(run_receipt: receipt_key).recent_first.first
        snapshot = existing_snapshot if existing_snapshot&.current_eligibility_comparison&.eligible?
        snapshot ||= NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "summary",
          run_receipt: receipt_key,
          sources: eligible_news
        )
      end
    elsif answer_type == POSITIONS
      if NewsArticleTestimonyService.commentary_eligible?(bill)
        eligible_news = NewsArticleTestimonyService.eligible_articles(bill).to_a
        if eligible_news.any?
          existing_snapshot = bill.news_article_source_snapshots.for_testimony.where(run_receipt: receipt_key).recent_first.first
          snapshot = existing_snapshot if existing_snapshot&.current_eligibility_comparison&.eligible?
          snapshot ||= NewsArticleSourceSnapshotService.capture!(
            bill: bill,
            purpose: "testimony",
            run_receipt: receipt_key,
            sources: eligible_news
          )
        end
      end
      if NewsOrgPositionGroundingService.reporting_eligible?(bill)
        eligible_reporting = NewsOrgPositionGroundingService.eligible_reporting_articles(bill).order(:id).to_a
        if eligible_reporting.any?
          existing_snapshot = bill.news_article_source_snapshots.for_summary.where(run_receipt: receipt_key).recent_first.first
          reporting_snapshot = existing_snapshot if existing_snapshot&.current_eligibility_comparison&.eligible?
          reporting_snapshot ||= NewsArticleSourceSnapshotService.capture!(
            bill: bill,
            purpose: "summary",
            run_receipt: receipt_key,
            sources: eligible_reporting
          )
        end
      end
    end

    builder = builder_for(
      bill, answer_type, active_categories,
      news_source_snapshot: snapshot,
      reporting_source_snapshot: reporting_snapshot
    )
    Llm::ClaudeBatchService::Item.new(
      custom_id: item_custom_id,
      prompt: Llm::PromptPayload.new(
        system_prompt: builder.system_prompt, user_message: builder.user_message
      ),
      model: model,
      schema: SCHEMA_HASHES.fetch(answer_type),
      validation_schema: VALIDATION_SCHEMAS.fetch(answer_type)
    )
  end

  # @lat: [[llm-summaries#Batch summarisation#Not every bill earns a batch item]]
  def self.build_all(bill:, eligibility:, model:, active_categories:, run_receipt: nil)
    types = [] #: Array[String]
    types << SUMMARY if eligibility.summary?
    types << POSITIONS if eligibility.positions?
    types.map do |answer_type|
      build(
        bill: bill, answer_type: answer_type, model: model,
        active_categories: active_categories, run_receipt: run_receipt
      )
    end
  end

  def self.builder_for(bill, answer_type, active_categories, news_source_snapshot: nil, reporting_source_snapshot: nil)
    case answer_type
    when SUMMARY then BillSummaryPromptBuilder.new(bill, active_categories: active_categories, news_source_snapshot: news_source_snapshot)
    when POSITIONS then BillPositionsPromptBuilder.new(bill, news_source_snapshot: news_source_snapshot, reporting_source_snapshot: reporting_source_snapshot)
    else raise ArgumentError, "unknown answer_type #{answer_type.inspect}"
    end
  end
  private_class_method :builder_for
end
