# frozen_string_literal: true

# @lat: [[llm-job-model-resolution-per-perform#Why the model is re-read on every perform, not memoized]]
# @lat: [[reference/bill-summary-retry-policy#Retry timing]]
# @lat: [[explanation/bill-summary-retry-policy#Why the retry window is about 20 minutes]]
class GenerateBillSummaryJob < ApplicationJob
  queue_as :background

  # @lat: [[bill-summary-error-message-budget#Why NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR exists at all]]
  MAX_GENERATION_ERROR_LENGTH = 500

  # @lat: [[bill-summary-nothing-to-generate-settlement#Why each stored message says what it says]]
  NOTHING_TO_GENERATE_ERROR =
    "nothing to summarize: this bill has no extracted text, no diff markdown, " \
    "and no testimony. Run the pipeline's extract-text and fetch-hearings " \
    "stages, or paste supplemental testimony, then generate again."

  # @lat: [[bill-summary-nothing-to-generate-settlement#Why each stored message says what it says]]
  NO_SOURCE_TEXT_ERROR =
    "no summary was generated: this bill has no extracted text and no diff " \
    "markdown, so there was nothing to summarize. The organization positions " \
    "below were generated from its testimony and are unaffected. Run the " \
    "pipeline's extract-text stage, or paste a summary, then generate again."

  # @lat: [[bill-summary-nothing-to-generate-settlement#Why each stored message says what it says]]
  # @lat: [[bill-summary-error-message-budget#Why NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR exists at all]]
  NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR =
    "no summary was generated: this bill has no extracted text and no diff " \
    "markdown, so there was nothing to summarize. The positions call also " \
    "failed: %{reason}. Retry to make the positions call again. The summary " \
    "call stays skipped until the bill has text, or until you paste a summary."

  # @lat: [[bill-summary-error-message-budget#Why NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR exists at all]]
  MAX_POSITIONS_FAILED_REASON_LENGTH =
    MAX_GENERATION_ERROR_LENGTH - NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR.sub("%{reason}", "").length

  # @lat: [[bill-summary-error-message-budget#POSITIONS_EVIDENCE_WITHDRAWN_REASON has to fit two homes]]
  POSITIONS_EVIDENCE_WITHDRAWN_REASON =
    "the testimony behind them changed while the run was in flight, so the new " \
    "positions were not saved. The drafts on this bill are the ones the last " \
    "run left. Generate again to draw positions from the testimony as it stands now."

  POSITIONS_DISCARDED_PREFIX = "positions not saved: "

  # @lat: [[bill-summary-nothing-to-generate-settlement#Why each stored message says what it says]]
  NO_SOURCE_TEXT_NO_POSITIONS_ERROR =
    "no summary was generated: this bill has no extracted text and no diff " \
    "markdown, so there was nothing to summarize. The positions call named no " \
    "organization, so there are no positions below either. Run the pipeline's " \
    "extract-text stage, or paste a summary, then generate again."

  # @lat: [[bill-llm-run-reclaim-timing#STALE_AFTER and the pre-call stale-job gate]]
  STALE_AFTER = 1.hour

  class BillSummaryError < StandardError; end

  class TransientBillSummaryError < BillSummaryError; end

  class DeterministicBillSummaryError < BillSummaryError; end

  retry_on TransientBillSummaryError, wait: :polynomially_longer, attempts: 3
  discard_on DeterministicBillSummaryError

  # @lat: [[llm-summaries#A run that fails before it starts still settles]]
  SETTLEABLE_ON_FAILURE = %w[generating pending].freeze

  # @lat: [[llm-summaries#A local server that is not running is said once]]
  HEALTH_PROBE_TIMEOUT_SECONDS = 2

  HEALTH_WARN_INTERVAL = 1.minute

  class << self
    def llm_endpoint_down?(route = nil)
      return false unless Rails.env.development?
      return false unless route ? route.llamacpp? : (Sway::Settings.llm.llm_provider == "llamacpp")

      !probe_llm_endpoint
    end

    def probe_llm_endpoint
      connection = Faraday.new(url: Sway::Settings.llm.llamacpp_base_url) do |f|
        f.options.timeout = HEALTH_PROBE_TIMEOUT_SECONDS
        f.options.open_timeout = HEALTH_PROBE_TIMEOUT_SECONDS
      end

      connection.get("models").success?
    rescue Faraday::Error, IOError, SystemCallError
      false
    end

    def warn_llm_endpoint_down(bill_id)
      last = @llm_endpoint_warned_at
      return if last && last > HEALTH_WARN_INTERVAL.ago

      @llm_endpoint_warned_at = Time.current
      SwayLogging.warn(
        "generate_bill_summary.llm_endpoint_down",
        bill_id: bill_id,
        base_url: Sway::Settings.llm.llamacpp_base_url,
        message: "the local model server did not answer its model list — skipping this " \
          "summary and any others until it is back"
      )
    end
  end

  # @lat: [[bill-summary-job-return-values#GenerateBillSummaryJob.perform return values]]
  # @lat: [[bill-summary-perform-return-contract#The caller could not tell from the outside, and used to guess wrong]]
  NOT_RUN = :not_run
  SETTLED = :settled
  # @lat: [[explanation/llm-summaries#Stand-downs are reported, not swallowed]]
  STOOD_DOWN = :stood_down

  # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
  def perform(bill_id, summarization_model: nil, summary_instructions: nil, reasoning_effort: nil)
    @summarization_model = summarization_model
    @summary_instructions = summary_instructions
    @reasoning_effort = reasoning_effort
    bill = Bill.includes(:bill_llm_provisioning).find_by(id: bill_id)
    return NOT_RUN unless bill

    provisioning = bill.bill_llm_provisioning

    # @lat: [[bill-llm-run-reclaim-timing#STALE_AFTER and the pre-call stale-job gate]]
    # @lat: [[bill-summary-paste-hand-off-rule#Why finding the stale-gate gap was deterministic, not a race]]
    if enqueued_at && enqueued_at < STALE_AFTER.ago.to_time
      SwayLogging.warn(
        "generate_bill_summary.skipped_stale",
        bill_id: bill_id,
        enqueued_at: enqueued_at,
        stale_after_seconds: STALE_AFTER.to_i
      )
      mark_stale_skipped!(provisioning)
      return NOT_RUN
    end

    provisioning ||= bill.create_bill_llm_provisioning!

    # @lat: [[bill-summary-supersede-gate#Why superseded_by_operator_paste? delegates rather than reads the column]]
    # @lat: [[explanation/llm-summaries#Batch summarisation#One reader decides whether a bill earns a batch item]]
    if SummaryItemEligibility.for(bill: bill, provisioning: provisioning).operator_paste?
      SwayLogging.warn(
        "generate_bill_summary.superseded_by_operator_paste",
        bill_id: bill.id,
        provisioning_id: provisioning.id,
        executions: executions,
        message: "an operator pasted a summary onto this row after it was armed — skipping both " \
          "adapter calls and settling the row onto the pasted body; Regenerate to override"
      )
      PipelineActivityLogger.log_summary_stood_down_for_paste!(bill: bill)
      settle_superseded_row(bill, provisioning)
      return STOOD_DOWN
    end

    # @lat: [[llm-job-model-resolution-per-perform#Why the model is re-read on every perform, not memoized]]
    # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    route = Llm::RouteResolver.resolve(
      purpose: :summary,
      per_run_override: @summarization_model,
      reasoning_effort: @reasoning_effort
    )

    if route.llamacpp? && self.class.llm_endpoint_down?(route)
      self.class.warn_llm_endpoint_down(bill.id)
      return NOT_RUN
    end

    return NOT_RUN unless arm_row_unless_owned!(bill, provisioning)

    SwayLogging.info(
      "generate_bill_summary.start",
      bill_id: bill.id,
      provisioning_id: provisioning.id,
      external_id: bill.external_id
    )

    # @lat: [[bill-summary-re-entry-guard#Why summary_run_id carries the marker]]
    resume_positions_only = false

    if resumed_after_purchase?(provisioning)
      if provisioning.draft_org_positions.nil? && SummaryItemEligibility.for(bill: bill, provisioning: provisioning).positions?
        SwayLogging.warn(
          "generate_bill_summary.resumed_owing_positions",
          bill_id: bill.id,
          provisioning_id: provisioning.id,
          summary_run_id: provisioning.summary_run_id,
          executions: executions,
          message: "a prior execution of this enqueue bought the summary and stopped before the " \
            "positions call landed — buying the positions half only, never the summary again"
        )
        resume_positions_only = true
      else
        settle_resumed_run(bill, provisioning)
        return SETTLED
      end
    end

    # @lat: [[bill-summary-arm-row-ownership#Decline logging, the row-gone case, and the pre-call clear#The pre-call clear: clear_stale_run_state_unless_superseded!]]
    unless resume_positions_only
      cleared = clear_stale_run_state_unless_superseded!(bill, provisioning)
      # @lat: [[bill-summary-nothing-to-generate-settlement#Arm 1: both spend gates closed#Why failed, not a new generating -> skipped edge]]
      return NOT_RUN if cleared == NOT_RUN
      return STOOD_DOWN if cleared == SETTLED
    end

    adapter = Llm::Client.build(provider: route.provider.to_s)
    model_at_call_time = route.api_model

    # @lat: [[bill-summary-call-preconditions#Why generate_bill_summary_job_spec.rb's default fixture sets bill.extracted_text, not just :with_diff_content]]
    active_categories = Category.where(active: true).order(:name).to_a

    eligible_news = bill.bill_news_articles.eligible_for_synthesis.order(:id).to_a
    news_snapshot = bill.news_article_source_snapshots.for_summary.find_by(run_receipt: job_id)
    news_snapshot ||= bill.news_article_source_snapshots.for_summary.find_by(run_receipt: provisioning.summary_run_id) if provisioning.summary_run_id.present?
    if news_snapshot.nil? && eligible_news.any?
      news_snapshot = NewsArticleSourceSnapshotService.capture!(
        bill: bill,
        purpose: "summary",
        run_receipt: job_id,
        sources: eligible_news
      )
    end

    builder = BillSummaryPromptBuilder.new(
      bill,
      active_categories: active_categories,
      summary_instructions: @summary_instructions,
      news_source_snapshot: news_snapshot
    )

    parsed = nil #: Hash[String, untyped]?
    adapter_call_made = false #: bool
    prompt_snapshot = nil #: BillSummaryPromptBuilder::Snapshot?
    prompt_built_at = nil #: ActiveSupport::TimeWithZone?
    prompt_facts = nil #: Hash[Symbol, untyped]?
    if resume_positions_only
      SwayLogging.warn(
        "generate_bill_summary.summary_call_skipped_on_resume",
        bill_id: bill.id,
        provisioning_id: provisioning.id,
        message: "the summary is already committed by an earlier execution of this enqueue — " \
          "only the positions call runs"
      )
    elsif SummaryItemEligibility.for(bill: bill, provisioning: provisioning).summary?
      payload = Llm::PromptPayload.new(
        system_prompt: builder.system_prompt,
        user_message: builder.user_message
      )

      prompt_snapshot = builder.snapshot
      prompt_built_at = Time.zone.now
      prompt_record = SummarySourcesReport.record(bill: bill, sources: prompt_snapshot.sources)
      prompt_facts = SummarySourcesRecordResource.new(prompt_record).serializable_hash #: Hash[Symbol, untyped]

      summary_kwargs = {}
      summary_kwargs[:reasoning_effort] = route.reasoning_effort if adapter.provider_label == "openrouter" && route.reasoning_effort.present?

      adapter_call_made = true
      parsed = adapter.generate_bill_summary(
        prompt: payload,
        model: model_at_call_time,
        schema: BILL_SUMMARY_SCHEMA_HASH,
        **summary_kwargs
      )
    else
      SwayLogging.warn(
        "generate_bill_summary.no_source_text",
        bill_id: bill.id,
        provisioning_id: provisioning.id,
        message: "no on-disk diff markdown and no extracted_text — skipping the summary call; " \
          "the testimony-gated positions call below is unaffected"
      )
    end

    if parsed
      citation_attrs = SummaryCitationValidator.verdict_attrs(bill: bill, payload: parsed)

      manifest_result = NewsSummaryManifestValidator.call(
        bill: bill,
        summary_markdown: parsed["summary_markdown"],
        news_usage: parsed["news_usage"],
        source_uses: parsed["source_uses"],
        snapshot: news_snapshot
      )

      grounding_result = nil
      if manifest_result.valid?
        if news_snapshot && manifest_result.news_usage == "cited"
          if parsed["source_uses"].is_a?(Array) && parsed["source_uses"].any?
            NewsArticleSourceUse.transaction do
              parsed["source_uses"].each do |use_payload|
                bna_id = use_payload["bill_news_article_id"]&.to_i
                tv_id = use_payload["text_version_id"]&.to_i
                claim_text = use_payload["claim_text"].to_s
                excerpt = (use_payload["evidence_excerpt"] || use_payload["verbatim_excerpt"]).to_s
                citation_url = use_payload["citation_url"].to_s

                news_snapshot.source_uses.create!(
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
            content: parsed["summary_markdown"],
            snapshot: news_snapshot,
            news_usage: manifest_result.news_usage,
            persist: true,
            route: route,
            adapter: adapter,
            model: model_at_call_time
          )
        end
      else
        grounding_result = manifest_result.structured_refusal
      end

      persisted = SummaryRunPersistGuard.call(
        bill, provisioning,
        citation_attrs.merge(
          llm_provider: adapter.provider_label,
          llm_model: model_at_call_time,
          llm_summary: parsed["summary_markdown"],
          llm_full_breakdown: parsed["full_breakdown_markdown"],
          news_usage: parsed["news_usage"],
          summary_run_id: job_id,
          llm_generated_at: Time.current
        ),
        news_source_snapshot: ((parsed["news_usage"] == "cited") ? news_snapshot : nil),
        grounding_result: grounding_result
      )
      # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
      if persisted == :vanished
        bail_on_vanished_row(bill, provisioning)
        return NOT_RUN
      end
      stand_down_mid_run(bill, provisioning) if persisted == :superseded
      return SETTLED unless persisted == :persisted

      record_prompt_snapshot(
        bill: bill, snapshot: prompt_snapshot, built_at: prompt_built_at, facts: prompt_facts,
        llm_model: model_at_call_time, llm_provider: adapter.provider_label
      )
    end

    # @lat: [[bill-summary-positions-evidence-digest#Why the testimony check reads committed state]]
    positions_evidence_digest = nil #: String?
    # @lat: [[explanation/llm-summaries#Batch summarisation#One reader decides whether a bill earns a batch item]]
    positions_attempted = SummaryRunLock.settle_under_lock(provisioning) {
      positions_evidence_digest = provisioning.testimony_digest
      SummaryItemEligibility.for(bill: bill, provisioning: provisioning).positions?
    } || false
    # @lat: [[bill-summary-nothing-to-generate-settlement#Arm 2: testimony present, but no bill text]]
    positions_failed_reason = nil #: String?
    # @lat: [[bill-summary-settle-completed-guard#positions_persisted vs positions_attempted: which one gates the recompute]]
    positions_persisted = false
    if positions_attempted
      begin
        # @lat: [[bill-summary-positions-error-handling#Why prompt construction sits inside the begin/rescue]]
        testimony_snapshot = nil
        if NewsArticleTestimonyService.commentary_eligible?(bill)
          testimony_snapshot = bill.news_article_source_snapshots.for_testimony.find_by(run_receipt: job_id)
          if testimony_snapshot.nil?
            eligible_testimony_articles = NewsArticleTestimonyService.eligible_articles(bill).to_a
            if eligible_testimony_articles.any?
              testimony_snapshot = NewsArticleSourceSnapshotService.capture!(
                bill: bill,
                purpose: "testimony",
                run_receipt: job_id,
                sources: eligible_testimony_articles
              )
            end
          end
        end

        # @lat: [[llm-summaries#LLM bill summaries#Output is validated, not trusted#Multi-chunk positions generation and deduplication]]
        positions_builder = BillPositionsPromptBuilder.new(
          bill,
          news_source_snapshot: testimony_snapshot,
          reporting_source_snapshot: news_snapshot
        )

        positions_kwargs = {}
        positions_kwargs[:reasoning_effort] = route.reasoning_effort if adapter.provider_label == "openrouter" && route.reasoning_effort.present?

        combined_draft_positions = []
        combined_news_testimonies = []

        positions_builder.prompt_payloads.each do |positions_payload|
          adapter_call_made = true
          chunk_parsed = adapter.generate_bill_positions(
            prompt: positions_payload,
            model: model_at_call_time,
            schema: BILL_POSITIONS_SCHEMA_HASH,
            **positions_kwargs
          )

          raw_chunk_positions = chunk_parsed["draft_org_positions"] || chunk_parsed[:draft_org_positions]
          combined_draft_positions.concat(raw_chunk_positions) if raw_chunk_positions.is_a?(Array)

          raw_chunk_news = chunk_parsed["draft_news_testimonies"] || chunk_parsed[:draft_news_testimonies]
          combined_news_testimonies.concat(raw_chunk_news) if raw_chunk_news.is_a?(Array)
        end

        deduped_news_testimonies = deduplicate_draft_news_testimonies(combined_news_testimonies)
        positions_parsed = {
          "draft_org_positions" => combined_draft_positions,
          "draft_news_testimonies" => deduped_news_testimonies
        }

        # @lat: [[news-org-position-persistence#Persistence callers]]
        # @lat: [[llm-summaries#LLM bill summaries#Output is validated, not trusted#Multi-chunk positions generation and deduplication]]
        filtered_positions = NewsOrgPositionGroundingService.filter_draft_positions(
          bill: bill,
          raw_positions: combined_draft_positions,
          snapshots: [news_snapshot, testimony_snapshot].compact,
          hearing_testimony_present: provisioning.testimony_present?
        ).first(BillPositionsPromptBuilder::MAX_DRAFT_POSITIONS)
        # @lat: [[bill-summary-positions-evidence-digest#Why the positions persist also stamps the purchase marker]]
        positions_attrs = {
          draft_org_positions: filtered_positions,
          summary_run_id: job_id
        } #: Hash[Symbol, untyped]
        positions_attrs[:generation_error] = nil if resume_positions_only || provisioning.generation_error.blank?

        positions_outcome = SummaryRunPersistGuard.call(
          bill, provisioning,
          positions_attrs,
          evidence_digest: positions_evidence_digest
        )
        if positions_outcome == :vanished
          bail_on_vanished_row(bill, provisioning)
          return NOT_RUN
        end
        if positions_outcome == :superseded
          stand_down_mid_run(bill, provisioning)
          return SETTLED
        end
        positions_persisted = positions_outcome == :persisted
        if positions_persisted && testimony_snapshot && positions_parsed["draft_news_testimonies"].present?
          NewsArticleTestimonyService.persist_drafts!(
            bill: bill,
            payload: positions_parsed,
            snapshot: testimony_snapshot,
            run_receipt: job_id
          )
          NewsArticleTestimonyService.publish_commentary!(
            bill: bill,
            snapshot: testimony_snapshot
          )
        end
        positions_failed_reason = discard_withdrawn_positions!(bill, provisioning) if
          positions_outcome == :evidence_withdrawn
      rescue => e
        # @lat: [[bill-summary-positions-error-handling#Why this differs from the summary call's error handling]]
        provisioning.reload
        error_message = Sway::Utf8.scrub(e.message)
        positions_failed_reason = error_message
        SwayLogging.warn(
          "generate_bill_summary.positions_failure",
          bill_id: bill.id,
          provisioning_id: provisioning.id,
          error_class: e.class.name,
          message: error_message
        )
        # @lat: [[bill-summary-positions-error-handling#Why "(the summary is valid)" is conditional on the row's own state]]
        # @lat: [[bill-summary-error-message-budget#Slicing the composed string, not a hand-counted prefix]]
        prefix = provisioning.llm_summary.present? ?
          "positions call failed (the summary is valid): " :
          "positions call failed: "
        provisioning.update_columns(
          generation_error: "#{prefix}#{error_message[0, MAX_GENERATION_ERROR_LENGTH]}"[0, MAX_GENERATION_ERROR_LENGTH]
        )
      end
    end
    # @lat: [[bill-summary-positions-error-handling#draft_org_positions is deliberately NOT touched here]]

    # @lat: [[bill-summary-category-assignment#When the response names categories that do not exist]]
    raw_categories = parsed && parsed["categories"]
    if parsed.nil?
      # @lat: [[bill-summary-category-assignment#generation_error and the parsed-is-nil case]]
    elsif active_categories.empty?
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
        # @lat: [[bill-summary-category-assignment#generation_error and the parsed-is-nil case]]
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

    # @lat: [[bill-summary-nothing-to-generate-settlement#Why each stored message says what it says]]
    if parsed.nil? && !positions_attempted && provisioning.llm_summary.blank?
      SwayLogging.warn(
        "generate_bill_summary.nothing_to_generate",
        bill_id: bill.id,
        provisioning_id: provisioning.id,
        message: "no bill text and no testimony — neither paid call was made; " \
          "settling `failed` rather than claiming a summary"
      )
      settle_nothing_to_generate(provisioning)
      return adapter_call_made ? SETTLED : STOOD_DOWN
    end

    # @lat: [[bill-summary-nothing-to-generate-settlement#Why each stored message says what it says]]
    if parsed.nil? && provisioning.llm_summary.blank?
      SwayLogging.warn(
        "generate_bill_summary.positions_only_no_summary",
        bill_id: bill.id,
        provisioning_id: provisioning.id,
        positions_failed: positions_failed_reason.present?,
        message: "testimony but no bill text — no summary was bought; " \
          "settling `failed` rather than claiming a summary"
      )
      settle_no_source_text(provisioning, positions_failed_reason: positions_failed_reason)
      return adapter_call_made ? SETTLED : STOOD_DOWN
    end

    # @lat: [[bill-summary-settle-completed-guard#The zero-adapter-calls path that still settles completed]]
    settle_completed(
      bill,
      provisioning,
      clear_generation_error: resume_positions_only && !positions_attempted,
      # @lat: [[bill-summary-settle-completed-guard#positions_persisted vs positions_attempted: which one gates the recompute]]
      recompute_score: !parsed.nil? || positions_persisted
    )
    SETTLED
  rescue Llm::TransportError => e
    wrapped = TransientBillSummaryError.new(e.message)
    record_failure(provisioning, wrapped)
    log_llm_failure(bill) { |b| PipelineActivityLogger.log_llm_provider_error!(bill: b, error_message: e.message) }
    raise wrapped
  rescue Llm::SchemaError => e
    wrapped = DeterministicBillSummaryError.new(e.message)
    record_failure(provisioning, wrapped)
    log_llm_failure(bill) do |b|
      PipelineActivityLogger.log_llm_json_parse_failure!(
        bill: b, error_message: e.message, raw_excerpt: e.message
      )
    end
    raise wrapped
  rescue => e
    # @lat: [[explanation/bill-summary-retry-policy#Why the catch-all rescue wraps as transient]]
    wrapped = TransientBillSummaryError.new("unexpected adapter error: #{e.class}: #{e.message}")
    record_failure(provisioning, wrapped)
    raise wrapped
  end

  private

  # @lat: [[bill-summary-re-entry-guard#Why job_id, and not enqueued_at]]
  def resumed_after_purchase?(provisioning)
    SummaryRunMarker.purchase_receipt?(provisioning.summary_run_id, job_id)
  end

  # @lat: [[bill-summary-re-entry-guard#settle_resumed_run: the same no-summary rule applies to the resumed path]]
  def settle_resumed_run(bill, provisioning)
    SwayLogging.warn(
      "generate_bill_summary.resumed_without_repurchase",
      bill_id: bill.id,
      provisioning_id: provisioning.id,
      summary_run_id: provisioning.summary_run_id,
      executions: executions,
      message: "a prior execution of this enqueue already bought and persisted everything this " \
        "run owed — skipping both adapter calls and settling the row"
    )

    if provisioning.llm_summary.blank?
      # @lat: [[explanation/llm-summaries#Batch summarisation#One reader decides whether a bill earns a batch item]]
      if SummaryItemEligibility.for(bill: bill, provisioning: provisioning).positions?
        settle_no_source_text(provisioning)
      else
        settle_nothing_to_generate(provisioning)
      end
      return
    end

    settle_completed(bill, provisioning, clear_generation_error: true)
  end

  # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
  def record_prompt_snapshot(bill:, snapshot:, built_at:, facts:, llm_model:, llm_provider:)
    return if snapshot.nil? || built_at.nil?

    BillSummaryPromptSnapshot.record!(
      bill: bill,
      snapshot: snapshot,
      built_at: built_at,
      summary_run_id: job_id,
      llm_model: llm_model,
      llm_provider: llm_provider,
      facts: facts || {}
    )
  rescue => e
    SwayLogging.warn(
      "generate_bill_summary.prompt_snapshot_not_recorded",
      bill_id: bill.id,
      job_id: job_id,
      error_class: e.class.name,
      message: e.message.to_s[0, 300]
    )
  end

  # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
  def bail_on_vanished_row(bill, provisioning)
    SwayLogging.warn(
      "generate_bill_summary.row_gone_after_paid_call",
      bill_id: bill.id,
      provisioning_id: provisioning.id,
      job_id: job_id,
      message: "the provisioning row was deleted while a paid call's answer was ready to persist — " \
        "the answer already paid for has nowhere to land"
    )
  end

  # @lat: [[llm-summaries#LLM bill summaries#Output is validated, not trusted#Multi-chunk positions generation and deduplication]]
  def deduplicate_draft_news_testimonies(raw_testimonies)
    return [] if raw_testimonies.blank?

    seen = Set.new
    raw_testimonies.filter_map do |entry|
      next unless entry.is_a?(Hash)

      bna_id = entry["bill_news_article_id"] || entry[:bill_news_article_id]
      tv_id = entry["text_version_id"] || entry[:text_version_id]
      key = [bna_id&.to_i, tv_id&.to_i]
      next if key.any?(&:nil?) || key.any?(&:zero?) || seen.include?(key)

      seen.add(key)
      entry
    end
  end

  # @lat: [[bill-summary-positions-evidence-digest#Discarding a positions purchase whose evidence moved: discard_withdrawn_positions!]]
  def discard_withdrawn_positions!(bill, provisioning)
    SwayLogging.warn(
      "generate_bill_summary.positions_evidence_withdrawn",
      bill_id: bill.id,
      provisioning_id: provisioning.id,
      job_id: job_id,
      message: "the testimony changed while the positions call was in flight — " \
        "the new positions were discarded and the existing drafts left as they are"
    )
    SummaryRunLock.settle_under_lock(provisioning) do
      unless SummaryRunMarker.operator_paste?(provisioning.summary_run_id)
        provisioning.update_columns(
          generation_error: "#{POSITIONS_DISCARDED_PREFIX}#{POSITIONS_EVIDENCE_WITHDRAWN_REASON}"[
            0, MAX_GENERATION_ERROR_LENGTH
          ],
          summary_run_id: job_id
        )
      end
    end
    POSITIONS_EVIDENCE_WITHDRAWN_REASON
  end

  # @lat: [[bill-summary-arm-row-ownership#The claim#What the arm deliberately does not decline on]]
  def arm_row_unless_owned!(bill, provisioning)
    status_at_load = provisioning.generation_status
    outcome = SummaryRunArm.call(provisioning: provisioning, job_id: job_id) do |decision|
      log_reclaimed_abandoned_run(bill, provisioning) if decision.log_reclaim?
    end
    armed = outcome.armed
    # @lat: [[bill-summary-arm-row-ownership#Decline logging, the row-gone case, and the pre-call clear]]
    decision_name = outcome.decision&.name

    # @lat: [[bill-summary-arm-row-ownership#Decline logging, the row-gone case, and the pre-call clear]]
    if armed.nil?
      SwayLogging.warn(
        "generate_bill_summary.row_gone_before_paid_calls",
        bill_id: bill.id,
        provisioning_id: provisioning.id,
        job_id: job_id,
        message: "the provisioning row was deleted before this run armed it — " \
          "stopping rather than buying two answers with nowhere to put them"
      )
      return false
    end
    return true unless armed == false

    SwayLogging.warn(
      "generate_bill_summary.row_owned_by_another_run",
      bill_id: bill.id,
      provisioning_id: provisioning.id,
      job_id: job_id,
      status_at_load: status_at_load,
      committed_status: provisioning.generation_status,
      summary_run_id: provisioning.summary_run_id,
      decision: decision_name,
      message: decline_message(decision_name)
    )
    PipelineActivityLogger.log_summary_stood_down_for_paste!(bill: bill) if
      decision_name == :paste_already_settled
    false
  end

  # @lat: [[bill-summary-arm-row-ownership#Decline logging, the row-gone case, and the pre-call clear]]
  def decline_message(decision_name)
    case decision_name
    when :paste_already_settled
      "an operator pasted a summary onto this row and it was not in flight, so nothing was " \
        "handed off — making no paid calls and leaving the hand-written body where it is"
    else
      "this row moved under this run, or is already generating for another one — " \
        "making no paid calls and leaving what that run committed alone"
    end
  end

  # @lat: [[bill-summary-arm-row-ownership#Decline logging, the row-gone case, and the pre-call clear]]
  def log_reclaimed_abandoned_run(bill, provisioning)
    SwayLogging.warn(
      "generate_bill_summary.reclaimed_abandoned_run",
      bill_id: bill.id,
      provisioning_id: provisioning.id,
      job_id: job_id,
      abandoned_since: provisioning.updated_at,
      abandoned_run_id: provisioning.summary_run_id,
      reclaim_after_seconds: GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER.to_i,
      message: "no writer touched this generating row for longer than the job's worst-case wall " \
        "clock, so the run that claimed it is gone — taking the row over rather than leaving the " \
        "bill with no summary and its summarize stage recorded as succeeded"
    )
  end

  # @lat: [[bill-summary-arm-row-ownership#Decline logging, the row-gone case, and the pre-call clear#The pre-call clear: clear_stale_run_state_unless_superseded!]]
  def clear_stale_run_state_unless_superseded!(bill, provisioning)
    cleared = SummaryRunLock.settle_under_lock(provisioning) do
      if SummaryRunMarker.operator_paste?(provisioning.summary_run_id)
        false
      else
        provisioning.update_columns(generation_error: nil)
        true
      end
    end
    # @lat: [[bill-summary-arm-row-ownership#Decline logging, the row-gone case, and the pre-call clear]]
    if cleared.nil?
      SwayLogging.warn(
        "generate_bill_summary.row_gone_before_paid_calls",
        bill_id: bill.id,
        provisioning_id: provisioning.id,
        job_id: job_id,
        message: "the provisioning row was deleted before this run made any paid call — " \
          "stopping rather than buying two answers with nowhere to put them"
      )
      return NOT_RUN
    end
    return :proceed unless cleared == false

    # @lat: [[bill-summary-arm-row-ownership#Decline logging, the row-gone case, and the pre-call clear#The pre-call clear: clear_stale_run_state_unless_superseded!]]
    stand_down_mid_run(bill, provisioning, recompute_score: false)
    SETTLED
  end

  # @lat: [[bill-summary-paste-hand-off-rule#settle_superseded_row: why the whole hand-off runs in one lock]]
  def settle_superseded_row(bill, provisioning)
    # @lat: [[bill-summary-paste-hand-off-rule#settle_superseded_row: why the whole hand-off runs in one lock]]
    SummaryRunLock.settle_under_lock(provisioning) do
      if provisioning.pending? || provisioning.generating?
        provisioning.start_generating! if provisioning.can_start_generating?

        # @lat: [[bill-summary-paste-hand-off-rule#settle_superseded_row: why the whole hand-off runs in one lock]]
        settle_completed(bill, provisioning, clear_generation_error: true, recompute_score: false)
        true
      else
        false
      end
    end
    # @lat: [[bill-summary-paste-hand-off-rule#settle_superseded_row: why the whole hand-off runs in one lock]]
  end

  # @lat: [[bill-summary-settle-completed-guard#stand_down_mid_run is the shared tail of both marker re-checks]]
  def stand_down_mid_run(bill, provisioning, recompute_score: true)
    SwayLogging.warn(
      "generate_bill_summary.superseded_mid_run",
      bill_id: bill.id,
      provisioning_id: provisioning.id,
      executions: executions,
      message: "an operator pasted a summary onto this row after this run was already under way — " \
        "discarding this run's output rather than overwriting hand-written work, and settling the " \
        "row onto the pasted body; Regenerate to override"
    )
    PipelineActivityLogger.log_summary_stood_down_for_paste!(bill: bill)
    settle_completed(
      bill, provisioning, clear_generation_error: true, recompute_score: recompute_score
    )
  end

  # @lat: [[bill-summary-settle-completed-guard#Why mark_completed! is guarded]]
  # @lat: [[bill-summary-settle-completed-guard#Why this method does not write llm_generated_at]]
  # @lat: [[llm-summaries#Batch summarisation#One settle shared by the job and the ingest]]
  def settle_completed(bill, provisioning, clear_generation_error: false, recompute_score: true)
    SummaryRunSettle.completed!(
      bill, provisioning,
      clear_generation_error: clear_generation_error, recompute_score: recompute_score
    )
  end

  # @lat: [[bill-summary-nothing-to-generate-settlement#Arm 2: testimony present, but no bill text]]
  def settle_nothing_to_generate(provisioning)
    SummaryRunLock.settle_under_lock(provisioning) do
      if !finish_deferred_paste!(provisioning) && provisioning.generating?
        provisioning.update_columns(
          generation_error: NOTHING_TO_GENERATE_ERROR[0, MAX_GENERATION_ERROR_LENGTH]
        )
        provisioning.mark_failed!
        PipelineActivityLogger.log_summary_skipped_no_source_text!(bill: provisioning.bill)
      end
    end
  end

  # @lat: [[bill-summary-nothing-to-generate-settlement#Arm 2: testimony present, but no bill text]]
  def settle_no_source_text(provisioning, positions_failed_reason: nil)
    SummaryRunLock.settle_under_lock(provisioning) do
      if !finish_deferred_paste!(provisioning) && provisioning.generating?
        provisioning.update_columns(
          generation_error: no_source_text_message(provisioning, positions_failed_reason)
        )
        provisioning.mark_failed!
        PipelineActivityLogger.log_summary_skipped_no_source_text!(bill: provisioning.bill)
      end
    end
  end

  # @lat: [[bill-summary-nothing-to-generate-settlement#Why each stored message says what it says]]
  def no_source_text_message(provisioning, positions_failed_reason)
    reason = positions_failed_reason.to_s
    if reason.present?
      # @lat: [[bill-summary-error-message-budget#Trimming a reason without breaking the sentence after it]]
      return format(
        NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR,
        reason: reason.truncate(MAX_POSITIONS_FAILED_REASON_LENGTH, omission: "…").delete_suffix(".")
      )[0, MAX_GENERATION_ERROR_LENGTH].to_s
    end

    return NO_SOURCE_TEXT_NO_POSITIONS_ERROR[0, MAX_GENERATION_ERROR_LENGTH].to_s if
      provisioning.draft_org_positions.blank? && provisioning.bill.news_article_testimonies.drafts.blank?

    NO_SOURCE_TEXT_ERROR[0, MAX_GENERATION_ERROR_LENGTH].to_s
  end

  # @lat: [[bill-llm-run-reclaim-timing#mark_stale_skipped!: resolving a stranded pending row]]
  def mark_stale_skipped!(provisioning)
    return if provisioning.nil?

    SummaryRunLock.settle_under_lock(provisioning) do
      provisioning.mark_skipped! if !finish_deferred_paste!(provisioning) && provisioning.pending?
    end
  end

  # @lat: [[bill-summary-paste-hand-off-rule#settle_superseded_row: why the whole hand-off runs in one lock]]
  def finish_deferred_paste!(provisioning)
    return false unless SummaryRunMarker.operator_paste?(provisioning.summary_run_id)
    return false unless provisioning.pending? || provisioning.generating?

    SwayLogging.warn(
      "generate_bill_summary.paste_hand_off_at_settle",
      bill_id: provisioning.bill_id,
      provisioning_id: provisioning.id,
      status: provisioning.generation_status,
      message: "an operator's paste owns this row's body — finishing the status hand-off " \
        "PasteSummaryService deferred instead of settling the row terminal"
    )
    PipelineActivityLogger.log_summary_stood_down_for_paste!(bill: provisioning.bill)
    SummaryRunRelease.hand_off_paste!(provisioning)
    true
  end

  # @lat: [[bill-summary-failure-logging#settle_failure!: the settle may not replace the error it was called to record]]
  def log_llm_failure(bill)
    return if bill.nil?

    # @lat: [[bill-summary-failure-logging#Why the Activity Log write is itself rescued]]
    yield bill
  rescue => e
    SwayLogging.warn(
      "generate_bill_summary.activity_log_write_failed",
      bill_id: bill&.id,
      error_class: e.class.name,
      message: e.message.to_s[0, 300]
    )
  end

  def record_failure(provisioning, error)
    return if provisioning.nil?

    SwayLogging.log_exception(
      "generate_bill_summary.failed",
      exception: error,
      bill_id: provisioning.bill_id,
      provisioning_id: provisioning.id
    )

    settle_failure!(provisioning, error)
  end

  # @lat: [[bill-summary-failure-logging#settle_failure!: the settle may not replace the error it was called to record]]
  def settle_failure!(provisioning, error)
    SummaryRunLock.settle_under_lock(provisioning) do
      if !finish_deferred_paste!(provisioning) && SETTLEABLE_ON_FAILURE.include?(provisioning.generation_status)
        provisioning.update_columns(generation_error: error.message.to_s[0, MAX_GENERATION_ERROR_LENGTH])
        provisioning.mark_failed!
      end
    end
  rescue => settle_error
    SwayLogging.log_exception(
      "generate_bill_summary.failure_settle_failed",
      exception: settle_error,
      bill_id: provisioning.bill_id,
      provisioning_id: provisioning.id
    )
  end
end
