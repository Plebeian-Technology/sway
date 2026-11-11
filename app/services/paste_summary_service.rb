# frozen_string_literal: true

# @lat: [[paste-summary-attrs-design#Why generation_error is cleared on every paste]]
class PasteSummaryService
  class InvalidNewsUsageError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super(errors.pluck(:message).join("; "))
    end
  end

  def initialize(bill:, actor:, summary_json:)
    @bill = bill
    @actor = actor
    @summary_json = summary_json.to_s
  end

  def call
    begin
      body = JSON.parse(@summary_json)
    rescue JSON::ParserError => e
      errors = [{path: "/", message: "Invalid JSON: #{e.message[0, 200]}"}]
      log_rejected(errors)
      return [:invalid_json, errors]
    end

    schema_errors = BILL_SUMMARY_SCHEMA.validate(body).map do |se|
      {path: se["data_pointer"].to_s, message: human_readable_schema_error(se)}
    end
    if schema_errors.any?
      log_rejected(schema_errors)
      return [:schema_invalid, schema_errors]
    end

    if body["news_usage"] == "none"
      prose_urls = SummaryCitationValidator.extract_prose_urls(body["summary_markdown"])
      official_url = SummaryCitationValidator.official_bill_url(@bill)
      news_urls = prose_urls.reject { |u| SummaryCitationValidator.official_url?(u, official_url) }
      if news_urls.any?
        errors = [{path: "/summary_markdown", message: "Declared no-news usage but content contains visible news citations: #{news_urls.join(", ")}"}]
        log_rejected(errors)
        return [:invalid_news_usage, errors]
      end
      if Array(body["source_uses"]).any?
        errors = [{path: "/source_uses", message: "Declared no-news usage but source-use manifest is not empty"}]
        log_rejected(errors)
        return [:invalid_news_usage, errors]
      end
    end

    provisioning = @bill.bill_llm_provisioning || @bill.build_bill_llm_provisioning
    # @lat: [[paste-summary-attrs-design#Why generation_error is cleared on every paste]]
    # @lat: [[paste-summary-attrs-design#The attrs hash: one field at a time]]
    # @type var attrs: Hash[Symbol, (ActiveSupport::TimeWithZone | String | bool | Array[String] | Array[Hash[String, untyped]] | Array[BillLlmProvisioning::draft_entry] | nil)]
    attrs = {
      llm_summary: body["summary_markdown"],
      llm_full_breakdown: body["full_breakdown_markdown"],
      llm_generated_at: Time.current,
      llm_provider: BillLlmProvisioning::OPERATOR_PASTE_PROVIDER,
      llm_model: nil,
      summary_run_id: SummaryRunMarker.operator_paste,
      generation_error: nil
    }
    # @lat: [[paste-summary-attrs-design#Why citations are re-checked on every paste]]
    attrs.merge!(SummaryCitationValidator.verdict_attrs(bill: @bill, payload: body))

    # @lat: [[paste-summary-audit-transaction-boundaries#The body write is atomic with its audit entry]]
    begin
      write_pasted_body!(provisioning, attrs, body)
    rescue InvalidNewsUsageError => e
      log_rejected(e.errors)
      return [:invalid_news_usage, e.errors]
    end

    # @lat: [[paste-summary-audit-transaction-boundaries#The body write is atomic with its audit entry]]
    settled = true
    begin
      settle_pasted_row!(provisioning)
    rescue => e
      settled = false
      SwayLogging.warn(
        "paste_summary.settle_failed",
        bill_id: @bill.id,
        provisioning_id: provisioning.id,
        generation_status: provisioning.generation_status,
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
    end

    assign_pasted_categories(body)

    return [:persisted_unsettled, []] unless settled || settlement_still_expected?(provisioning)

    [:persisted, []]
  end

  private

  # @lat: [[paste-summary-audit-transaction-boundaries#settlement_still_expected?: full reasoning (superseding the note above)]]
  def settlement_still_expected?(provisioning)
    provisioning.reload
    provisioning.pending? || provisioning.generating? || provisioning.completed?
  rescue => e
    SwayLogging.warn(
      "paste_summary.settle_state_unknown",
      bill_id: @bill.id,
      provisioning_id: provisioning.id,
      error_class: e.class.name,
      message: e.message.to_s[0, 300]
    )
    false
  end

  # @lat: [[paste-summary-category-assignment-failure-handling#An empty pasted category list does not clear the bill's categories]]
  def assign_pasted_categories(body)
    return unless body.key?("categories")

    raw_categories = Array(body["categories"])
    if raw_categories.empty?
      SwayLogging.warn(
        "paste_summary.empty_categories_ignored",
        bill_id: @bill.id,
        message: "the pasted categories list was empty, so the bill's categories were left as they are — " \
          "remove them from the bill's Categories controls if that is what was wanted"
      )
      return
    end

    active_categories = Category.where(active: true).to_a
    return if active_categories.empty?

    BillCategoryAssigner.new(@bill, raw_categories, active_categories).call
  rescue Llm::SchemaError => e
    SwayLogging.warn(
      "paste_summary.categories_not_matched",
      bill_id: @bill.id,
      raw_categories: raw_categories,
      message: e.message
    )
  rescue => e
    SwayLogging.warn(
      "paste_summary.categories_assignment_failed",
      bill_id: @bill.id,
      error_class: e.class.name,
      message: e.message.to_s[0, 300]
    )
  end

  # @lat: [[paste-summary-status-reuse-and-pending-bug#Why there is no pasted status]]
  def settle_pasted_row!(provisioning)
    provisioning.with_lock do
      # @lat: [[paste-summary-status-reuse-and-pending-bug#Why settle_pasted_row! re-reads the status under the lock]]
      if provisioning.pending? || provisioning.generating?
        # @lat: [[paste-summary-attrs-design#settle_pasted_row!: why the deferred-settle log message names the re-read]]
        SwayLogging.warn(
          "paste_summary.settle_deferred_run_in_flight",
          bill_id: @bill.id,
          provisioning_id: provisioning.id,
          generation_status: provisioning.generation_status,
          message: "pasted summary body persisted but the row was left in flight — a queued or " \
            "running GenerateBillSummaryJob owns its status and will settle it; that job reads the " \
            "operator-paste marker on summary_run_id both before it buys and again under the row " \
            "lock before each persist, so it stands down rather than overwriting the pasted body"
        )
        next
      end
      next if provisioning.completed?

      provisioning.enqueue! if provisioning.can_enqueue?
      provisioning.start_generating! if provisioning.can_start_generating?
      provisioning.mark_completed! if provisioning.can_mark_completed?
    end
  end

  # @lat: [[paste-summary-draft-positions-lock-merge#What the merge is doing]]
  def write_pasted_body!(provisioning, attrs, body)
    @bill.with_lock do
      if provisioning.new_record?
        ApplicationRecord.transaction { commit_pasted_body!(provisioning, attrs, body) }
      else
        provisioning.with_lock { commit_pasted_body!(provisioning, attrs, body) }
      end
    end
  end

  def commit_pasted_body!(provisioning, attrs, body)
    BillSummaryRevision.ensure_baseline!(@bill, provisioning: provisioning)

    snapshot = nil
    if body["news_usage"] == "cited"
      bna_ids = Array(body["source_uses"]).map { |u| u["bill_news_article_id"] || u[:bill_news_article_id] }.compact.uniq
      draft_bna_ids = Array(body["draft_org_positions"]).filter_map do |d|
        d["bill_news_article_id"] || d[:bill_news_article_id] if d.is_a?(Hash)
      end.uniq
      prose_urls = SummaryCitationValidator.extract_prose_urls(body["summary_markdown"].to_s)
      official_url = SummaryCitationValidator.official_bill_url(@bill)
      news_urls = (prose_urls + Array(body["cited_news_urls"])).uniq.reject do |u|
        SummaryCitationValidator.official_url?(u, official_url)
      end
      url_matched_ids = if news_urls.any?
        @bill.bill_news_articles.synthesis_eligible.includes(:news_article).select do |bna|
          news_urls.include?(bna.news_article&.canonical_url)
        end.map(&:id)
      else
        []
      end
      bnas = @bill.bill_news_articles.synthesis_eligible.where(id: (bna_ids + draft_bna_ids + url_matched_ids).uniq)
      if bnas.any?
        begin
          snapshot = NewsArticleSourceSnapshotService.capture!(
            bill: @bill,
            purpose: "summary",
            actor: @actor,
            sources: bnas.to_a,
            source_uses_attributes: Array(body["source_uses"])
          )
        rescue ActiveRecord::RecordInvalid, ActiveRecord::InvalidForeignKey => e
          raise InvalidNewsUsageError.new([{path: "/source_uses", message: e.message}])
        end
      end

      manifest_result = NewsSummaryManifestValidator.call(
        bill: @bill,
        summary_markdown: body["summary_markdown"],
        news_usage: "cited",
        source_uses: body["source_uses"],
        snapshot: snapshot
      )
      unless manifest_result.valid?
        raise InvalidNewsUsageError.new(
          manifest_result.errors.map { |msg| {path: "/source_uses", message: msg} }
        )
      end
    end

    provisioning.assign_attributes(attrs.merge(draft_positions_attrs(body, provisioning)))
    provisioning.save!
    # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
    BillSummaryPromptSnapshot.forget!(bill: @bill)
    PipelineActivityLogger.log_paste_summary_accepted!(bill: @bill, actor: @actor)

    if body["summary_markdown"].present?
      # @lat: [[bill-creator-summary-tab#Planned recoverable summary history]]
      BillSummaryRevision.record_revision!(
        bill: @bill,
        summary_markdown: body["summary_markdown"],
        origin: "operator_paste",
        actor: @actor,
        publication_role: "draft",
        review_state: "unknown",
        llm_provider: nil,
        llm_model: nil,
        news_source_snapshot: snapshot
      )
    end
  end

  # @lat: [[paste-summary-draft-positions-testimony-guard#Why a non-empty list requires testimony]]
  # @lat: [[news-org-position-persistence#Persistence callers]]
  def draft_positions_attrs(body, provisioning)
    return {} unless body.key?("draft_org_positions")

    pasted = body["draft_org_positions"]
    return {draft_org_positions: []} if Array(pasted).empty?

    snapshots = [
      @bill.news_article_source_snapshots.for_summary.recent_first.first,
      @bill.news_article_source_snapshots.for_testimony.recent_first.first
    ].compact

    filtered = NewsOrgPositionGroundingService.filter_draft_positions(
      bill: @bill,
      raw_positions: pasted,
      snapshots: snapshots,
      hearing_testimony_present: provisioning.testimony_present?
    )

    if filtered.any?
      preserved = BillLlmProvisioning.draft_org_positions_preserving_marks(
        provisioning.draft_org_positions, filtered
      )
      return {draft_org_positions: preserved}
    end

    SwayLogging.warn(
      "paste_summary.positions_ignored_no_testimony",
      bill_id: @bill.id,
      ignored_count: Array(pasted).length,
      message: "pasted draft_org_positions dropped — requires testimony (extracted or supplemental) " \
        "or grounded news reporting before any org position may be persisted; the summary body was accepted"
    )
    {}
  end

  def log_rejected(errors)
    PipelineActivityLogger.log_paste_summary_rejected!(
      bill: @bill, actor: @actor, errors: errors.pluck(:message)
    )
  end

  def human_readable_schema_error(schema_error)
    case schema_error["type"]
    when "required"
      missing = schema_error["details"].is_a?(Hash) ? schema_error["details"]["missing_keys"] : nil
      Array(missing).any? ? "missing required key(s): #{Array(missing).join(", ")}" : "is required"
    when "enum"
      allowed = schema_error.dig("schema", "enum")
      Array(allowed).any? ? "must be one of: #{Array(allowed).join(", ")}" : "invalid enum value"
    else
      schema_error["error"].to_s.presence || "invalid value"
    end
  end
end
