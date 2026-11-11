# frozen_string_literal: true

# @lat: [[news-article-evidence#Manual and historical publication]]
# @lat: [[news-gate#News publication gating]]
class ManualNewsSummaryPublicationService
  class Result
    attr_reader :status, :errors, :reasons, :revision, :snapshot, :grounding_result, :eligibility_comparison

    def initialize(
      status:,
      errors: [],
      reasons: [],
      revision: nil,
      snapshot: nil,
      grounding_result: nil,
      eligibility_comparison: nil
    )
      @status = status
      @errors = errors || []
      @reasons = reasons || []
      @revision = revision
      @snapshot = snapshot
      @grounding_result = grounding_result
      @eligibility_comparison = eligibility_comparison
    end

    def success?
      @status == :published
    end

    def published?
      @status == :published
    end

    def publishable?
      @status == :published
    end

    def draft?
      %i[draft review_draft stale_version_lock invalid_news_usage missing_news_usage empty_source_uses unsupported_grounding indeterminate_grounding].include?(@status)
    end
  end

  def self.publish!(
    bill:,
    summary_markdown: nil,
    summary: nil,
    actor: nil,
    origin: "operator_edit",
    news_usage: nil,
    source_uses: nil,
    snapshot: nil,
    snapshot_id: nil,
    restored_from: nil,
    review_state: nil,
    dry_run: false
  )
    new(
      bill: bill,
      summary_markdown: summary_markdown || summary,
      actor: actor,
      origin: origin,
      news_usage: news_usage,
      source_uses: source_uses,
      snapshot: snapshot,
      snapshot_id: snapshot_id,
      restored_from: restored_from,
      review_state: review_state,
      dry_run: dry_run
    ).publish!
  end

  class << self
    alias_method :call, :publish!
  end

  def initialize(
    bill:,
    summary_markdown:,
    actor:,
    origin: "operator_edit",
    news_usage: nil,
    source_uses: nil,
    snapshot: nil,
    snapshot_id: nil,
    restored_from: nil,
    review_state: nil,
    dry_run: false
  )
    @bill = bill
    @summary_markdown = summary_markdown.to_s
    @actor = actor
    @origin = origin.to_s
    @news_usage = news_usage
    @source_uses = source_uses
    @snapshot = snapshot
    @snapshot_id = snapshot_id
    @restored_from = restored_from
    @review_state = review_state
    @dry_run = dry_run
  end

  def publish!
    if @dry_run
      if @origin == "restoration"
        publish_restoration!
      else
        publish_manual_edit!
      end
    else
      @bill.with_lock do
        ensure_baseline!

        if @origin == "restoration"
          publish_restoration!
        else
          publish_manual_edit!
        end
      end
    end
  end

  private

  def ensure_baseline!
    return if @dry_run
    current_summary = @bill.summary
    return if current_summary.blank? || @bill.bill_summary_revisions.any? || current_summary.strip == Bill::SUMMARY_PLACEHOLDER

    BillSummaryRevision.record_revision!(
      bill: @bill,
      summary_markdown: @bill.summary,
      origin: "initial_baseline",
      publication_role: "published",
      review_state: "unknown"
    )
  end

  def publish_restoration!
    effective_snapshot = @snapshot || (@snapshot_id ? NewsArticleSourceSnapshot.find_by(id: @snapshot_id) : nil) || @restored_from&.news_source_snapshot

    if effective_snapshot.present?
      if effective_snapshot.bill_id != @bill.id
        draft_rev = record_draft_revision(nil)
        return Result.new(
          status: :invalid_news_usage,
          errors: ["Snapshot does not belong to bill"],
          revision: draft_rev,
          snapshot: effective_snapshot
        )
      end

      news_usage_str = @news_usage&.to_s&.strip
      if news_usage_str == "none"
        draft_rev = record_draft_revision(effective_snapshot)
        return Result.new(
          status: :invalid_news_usage,
          errors: ["Declared no-news usage but snapshot is present for restored revision"],
          revision: draft_rev,
          snapshot: effective_snapshot
        )
      end

      if news_usage_str.present? && !%w[none cited].include?(news_usage_str)
        draft_rev = record_draft_revision(effective_snapshot)
        return Result.new(
          status: :missing_news_usage,
          errors: ["Missing or invalid news_usage declaration: #{@news_usage.inspect}"],
          revision: draft_rev,
          snapshot: effective_snapshot
        )
      end

      comparison = effective_snapshot.current_eligibility_comparison
      unless comparison.eligible?
        draft_rev = record_draft_revision(effective_snapshot)
        return Result.new(
          status: :stale_version_lock,
          errors: comparison.mismatches,
          reasons: comparison.stale_reasons,
          revision: draft_rev,
          snapshot: effective_snapshot,
          eligibility_comparison: comparison
        )
      end

      grounding = NewsClaimGroundingService.call(
        bill: @bill,
        content: @summary_markdown,
        snapshot: effective_snapshot,
        news_usage: "cited"
      )
      unless grounding.supported?
        draft_rev = record_draft_revision(effective_snapshot)
        return Result.new(
          status: grounding.indeterminate? ? :indeterminate_grounding : :unsupported_grounding,
          errors: grounding.errors,
          revision: draft_rev,
          snapshot: effective_snapshot,
          grounding_result: grounding
        )
      end

      commit_published!(effective_snapshot)
    else
      news_usage_str = @news_usage&.to_s&.strip

      if news_usage_str.blank?
        draft_rev = record_draft_revision(nil)
        return Result.new(
          status: :review_draft,
          errors: ["Legacy revision without snapshot requires an explicit news_usage declaration or evidence review before publication"],
          revision: draft_rev
        )
      end

      if news_usage_str == "none"
        prose_news_urls = extract_prose_news_urls
        if prose_news_urls.any?
          draft_rev = record_draft_revision(nil)
          return Result.new(
            status: :invalid_news_usage,
            errors: ["Declared no-news usage but prose cites news reporting: #{prose_news_urls.join(", ")}"],
            revision: draft_rev
          )
        end

        if @source_uses.present? && Array(@source_uses).any?
          draft_rev = record_draft_revision(nil)
          return Result.new(
            status: :invalid_news_usage,
            errors: ["Declared no-news usage but source-use manifest is not empty"],
            revision: draft_rev
          )
        end

        grounding = NewsClaimGroundingService.call(
          bill: @bill,
          content: @summary_markdown,
          news_usage: "none",
          persist: false
        )
        unless grounding.supported?
          draft_rev = record_draft_revision(nil)
          return Result.new(
            status: :invalid_news_usage,
            errors: grounding.errors,
            revision: draft_rev,
            grounding_result: grounding
          )
        end

        commit_published!(nil)
      elsif news_usage_str == "cited"
        effective_uses = normalized_source_uses
        prose_news_urls = extract_prose_news_urls
        if effective_uses.empty? && prose_news_urls.empty?
          draft_rev = record_draft_revision(nil)
          return Result.new(
            status: :empty_source_uses,
            errors: ["Declared cited news usage but source-use manifest is empty"],
            revision: draft_rev
          )
        end

        grounding = NewsClaimGroundingService.call(
          bill: @bill,
          content: @summary_markdown,
          source_uses: effective_uses,
          news_usage: "cited",
          persist: false
        )
        unless grounding.supported?
          draft_rev = record_draft_revision(nil)
          return Result.new(
            status: grounding.indeterminate? ? :indeterminate_grounding : :unsupported_grounding,
            errors: grounding.errors,
            revision: draft_rev,
            grounding_result: grounding
          )
        end

        return Result.new(status: :published, snapshot: nil, grounding_result: grounding) if @dry_run

        bnas = resolve_cited_bill_news_articles(effective_uses, prose_news_urls)

        captured_snapshot = NewsArticleSourceSnapshotService.capture!(
          bill: @bill,
          purpose: "summary",
          actor: @actor,
          sources: bnas,
          source_uses_attributes: effective_uses
        )

        comparison = captured_snapshot.current_eligibility_comparison
        unless comparison.eligible?
          draft_rev = record_draft_revision(captured_snapshot)
          return Result.new(
            status: :stale_version_lock,
            errors: comparison.mismatches,
            reasons: comparison.stale_reasons,
            revision: draft_rev,
            snapshot: captured_snapshot,
            eligibility_comparison: comparison
          )
        end

        final_grounding = NewsClaimGroundingService.call(
          bill: @bill,
          content: @summary_markdown,
          snapshot: captured_snapshot,
          news_usage: "cited",
          persist: true
        )
        unless final_grounding.supported?
          draft_rev = record_draft_revision(captured_snapshot)
          return Result.new(
            status: final_grounding.indeterminate? ? :indeterminate_grounding : :unsupported_grounding,
            errors: final_grounding.errors,
            revision: draft_rev,
            snapshot: captured_snapshot,
            grounding_result: final_grounding
          )
        end

        commit_published!(captured_snapshot)
      else
        draft_rev = record_draft_revision(nil)
        Result.new(
          status: :missing_news_usage,
          errors: ["Missing or invalid news_usage declaration: #{@news_usage.inspect}"],
          revision: draft_rev
        )
      end
    end
  end

  def publish_manual_edit!
    news_usage_str = @news_usage&.to_s&.strip

    if news_usage_str.blank? || !%w[none cited].include?(news_usage_str)
      draft_rev = record_draft_revision(nil)
      return Result.new(
        status: :missing_news_usage,
        errors: ["Missing or invalid news_usage declaration: #{@news_usage.inspect}"],
        revision: draft_rev
      )
    end

    if news_usage_str == "none"
      if @source_uses.present? && Array(@source_uses).any?
        draft_rev = record_draft_revision(nil)
        return Result.new(
          status: :invalid_news_usage,
          errors: ["Declared no-news usage but source-use manifest is not empty"],
          revision: draft_rev
        )
      end

      grounding = NewsClaimGroundingService.call(
        bill: @bill,
        content: @summary_markdown,
        news_usage: "none",
        persist: false
      )
      unless grounding.supported?
        draft_rev = record_draft_revision(nil)
        return Result.new(
          status: :invalid_news_usage,
          errors: grounding.errors,
          revision: draft_rev,
          grounding_result: grounding
        )
      end

      commit_published!(nil)
    else
      effective_uses = normalized_source_uses
      prose_news_urls = extract_prose_news_urls

      if effective_uses.empty? && prose_news_urls.empty? && @snapshot.nil? && @snapshot_id.nil?
        draft_rev = record_draft_revision(nil)
        return Result.new(
          status: :empty_source_uses,
          errors: ["Declared cited news usage but source-use manifest is empty"],
          revision: draft_rev
        )
      end

      effective_snapshot = @snapshot || (@snapshot_id ? NewsArticleSourceSnapshot.find_by(id: @snapshot_id) : nil)

      if effective_snapshot.present?
        if effective_snapshot.bill_id != @bill.id
          draft_rev = record_draft_revision(nil)
          return Result.new(
            status: :unsupported_grounding,
            errors: ["News source snapshot belongs to another bill"],
            revision: draft_rev
          )
        end

        comparison = effective_snapshot.current_eligibility_comparison
        unless comparison.eligible?
          draft_rev = record_draft_revision(effective_snapshot)
          return Result.new(
            status: :stale_version_lock,
            errors: comparison.mismatches,
            reasons: comparison.stale_reasons,
            revision: draft_rev,
            snapshot: effective_snapshot,
            eligibility_comparison: comparison
          )
        end

        grounding = NewsClaimGroundingService.call(
          bill: @bill,
          content: @summary_markdown,
          snapshot: effective_snapshot,
          news_usage: "cited"
        )
        unless grounding.supported?
          draft_rev = record_draft_revision(effective_snapshot)
          return Result.new(
            status: grounding.indeterminate? ? :indeterminate_grounding : :unsupported_grounding,
            errors: grounding.errors,
            revision: draft_rev,
            snapshot: effective_snapshot,
            grounding_result: grounding
          )
        end

        commit_published!(effective_snapshot)
      else
        grounding = NewsClaimGroundingService.call(
          bill: @bill,
          content: @summary_markdown,
          source_uses: effective_uses,
          news_usage: "cited",
          persist: false
        )
        unless grounding.supported?
          draft_rev = record_draft_revision(nil)
          return Result.new(
            status: grounding.indeterminate? ? :indeterminate_grounding : :unsupported_grounding,
            errors: grounding.errors,
            revision: draft_rev,
            grounding_result: grounding
          )
        end

        return Result.new(status: :published, snapshot: nil, grounding_result: grounding) if @dry_run

        bnas = resolve_cited_bill_news_articles(effective_uses, prose_news_urls)

        captured_snapshot = NewsArticleSourceSnapshotService.capture!(
          bill: @bill,
          purpose: "summary",
          actor: @actor,
          sources: bnas,
          source_uses_attributes: effective_uses
        )

        comparison = captured_snapshot.current_eligibility_comparison
        unless comparison.eligible?
          draft_rev = record_draft_revision(captured_snapshot)
          return Result.new(
            status: :stale_version_lock,
            errors: comparison.mismatches,
            reasons: comparison.stale_reasons,
            revision: draft_rev,
            snapshot: captured_snapshot,
            eligibility_comparison: comparison
          )
        end

        final_grounding = NewsClaimGroundingService.call(
          bill: @bill,
          content: @summary_markdown,
          snapshot: captured_snapshot,
          news_usage: "cited",
          persist: true
        )
        unless final_grounding.supported?
          draft_rev = record_draft_revision(captured_snapshot)
          return Result.new(
            status: final_grounding.indeterminate? ? :indeterminate_grounding : :unsupported_grounding,
            errors: final_grounding.errors,
            revision: draft_rev,
            snapshot: captured_snapshot,
            grounding_result: final_grounding
          )
        end

        commit_published!(captured_snapshot)
      end
    end
  end

  def commit_published!(snapshot)
    return Result.new(status: :published, snapshot: snapshot) if @dry_run

    if snapshot.present?
      comparison = snapshot.current_eligibility_comparison
      unless comparison.eligible?
        draft_rev = record_draft_revision(snapshot)
        return Result.new(
          status: :stale_version_lock,
          errors: comparison.mismatches,
          reasons: comparison.stale_reasons,
          revision: draft_rev,
          snapshot: snapshot,
          eligibility_comparison: comparison
        )
      end
    end

    @bill.update!(summary: @summary_markdown)

    pub_rev = BillSummaryRevision.record_revision!(
      bill: @bill,
      summary_markdown: @summary_markdown,
      origin: @origin,
      actor: @actor,
      publication_role: "published",
      review_state: @review_state || @restored_from&.review_state || "reviewed",
      llm_provider: @restored_from&.llm_provider,
      llm_model: @restored_from&.llm_model,
      restored_from: @restored_from,
      news_source_snapshot: snapshot
    )

    Result.new(status: :published, revision: pub_rev, snapshot: snapshot)
  end

  def record_draft_revision(snapshot)
    return nil if @dry_run

    valid_snapshot = (snapshot&.bill_id == @bill.id) ? snapshot : nil

    BillSummaryRevision.record_revision!(
      bill: @bill,
      summary_markdown: @summary_markdown,
      origin: @origin,
      actor: @actor,
      publication_role: "draft",
      review_state: @review_state || @restored_from&.review_state || "reviewed",
      llm_provider: @restored_from&.llm_provider,
      llm_model: @restored_from&.llm_model,
      restored_from: @restored_from,
      news_source_snapshot: valid_snapshot
    )
  end

  def extract_prose_news_urls
    prose_urls = SummaryCitationValidator.extract_prose_urls(@summary_markdown)
    official_url = SummaryCitationValidator.official_bill_url(@bill)

    prose_urls.reject do |url|
      SummaryCitationValidator.official_url?(url, official_url)
    end
  end

  def resolve_cited_bill_news_articles(effective_uses, prose_news_urls)
    bna_ids = effective_uses.map { |u| u[:bill_news_article_id] || u["bill_news_article_id"] }.compact.uniq
    url_matched_ids = if prose_news_urls.any?
      @bill.bill_news_articles.includes(:news_article).select do |bna|
        prose_news_urls.include?(bna.news_article&.canonical_url)
      end.map(&:id)
    else
      []
    end
    @bill.bill_news_articles.where(id: (bna_ids + url_matched_ids).uniq).to_a
  end

  def normalized_source_uses
    Array(@source_uses).map do |u|
      if u.respond_to?(:to_unsafe_h)
        u.to_unsafe_h.deep_symbolize_keys
      elsif u.respond_to?(:to_h)
        u.to_h.deep_symbolize_keys
      else
        u
      end
    end
  end
end
