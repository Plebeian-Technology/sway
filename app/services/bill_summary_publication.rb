# frozen_string_literal: true

# @lat: [[news-gate#News publication gating]]
class BillSummaryPublication
  class Decision
    attr_reader :publishable, :status, :errors, :reasons, :verdict, :grounding_result, :eligibility_comparison

    def initialize(
      publishable:,
      status: :publishable,
      errors: [],
      reasons: [],
      verdict: "supported",
      grounding_result: nil,
      eligibility_comparison: nil
    )
      @publishable = publishable
      @status = status
      @errors = errors || []
      @reasons = reasons || []
      @verdict = verdict
      @grounding_result = grounding_result
      @eligibility_comparison = eligibility_comparison
    end

    def publishable?
      @publishable
    end

    def supported?
      @publishable
    end
  end

  Evaluation = Decision

  def self.publishable?(bill:, previous_draft:)
    published = bill.summary.to_s

    return true if published.strip.empty?
    return true if published.strip == Bill::SUMMARY_PLACEHOLDER

    latest_published = if bill.bill_summary_revisions.loaded?
      bill.bill_summary_revisions
        .select { |r| r.publication_role == "published" }
        .max_by { |r| [r.created_at || Time.zone.at(0), r.id || 0] }
    else
      bill.bill_summary_revisions
        .where(publication_role: "published")
        .order(created_at: :desc, id: :desc)
        .first
    end

    if latest_published && %w[restoration operator_edit operator_paste].include?(latest_published.origin)
      return false
    end

    published == previous_draft.to_s
  end

  def self.evaluate(
    bill:,
    previous_draft: nil,
    content: nil,
    summary_markdown: nil,
    news_usage: nil,
    snapshot: nil,
    news_source_snapshot: nil,
    grounding_result: nil,
    source_uses: nil
  )
    text = (content || summary_markdown).to_s
    snap = snapshot || news_source_snapshot

    unless publishable?(bill: bill, previous_draft: previous_draft)
      return Decision.new(
        publishable: false,
        status: :operator_overwrite,
        errors: ["The published summary was modified by an operator and cannot be overwritten by model generation"],
        reasons: [:operator_overwrite_blocked],
        verdict: "unsupported"
      )
    end

    usage_str = news_usage&.to_s&.strip

    if usage_str.blank? || !%w[none cited].include?(usage_str)
      return Decision.new(
        publishable: false,
        status: :invalid_news_usage,
        errors: ["Missing or invalid news_usage declaration: #{news_usage.inspect}"],
        reasons: [:invalid_news_usage],
        verdict: "unsupported",
        grounding_result: grounding_result
      )
    end

    usage = usage_str

    if usage == "none"
      grounding = grounding_result || NewsClaimGroundingService.call(
        bill: bill,
        content: text,
        source_uses: source_uses,
        snapshot: nil,
        news_usage: "none",
        persist: false
      )

      if grounding.supported?
        return Decision.new(
          publishable: true,
          status: :publishable,
          errors: [],
          reasons: [],
          verdict: "none",
          grounding_result: grounding
        )
      else
        return Decision.new(
          publishable: false,
          status: :invalid_news_usage,
          errors: grounding.errors,
          reasons: [:undeclared_news_links],
          verdict: grounding.verdict,
          grounding_result: grounding
        )
      end
    end

    if snap.nil?
      return Decision.new(
        publishable: false,
        status: :missing_snapshot,
        errors: ["Missing or invalid news source snapshot for cited news usage"],
        reasons: [:missing_snapshot],
        verdict: "unsupported"
      )
    end

    if snap.bill_id != bill.id
      return Decision.new(
        publishable: false,
        status: :invalid_snapshot,
        errors: ["News source snapshot belongs to a different bill"],
        reasons: [:cross_bill_snapshot],
        verdict: "unsupported"
      )
    end

    grounding = grounding_result || NewsClaimGroundingService.call(
      bill: bill,
      content: text,
      snapshot: snap,
      news_usage: "cited",
      persist: true
    )

    unless grounding.supported?
      status = grounding.indeterminate? ? :indeterminate_grounding : :unsupported_grounding
      reason = grounding.indeterminate? ? :grounding_indeterminate : :grounding_unsupported
      return Decision.new(
        publishable: false,
        status: status,
        errors: grounding.errors,
        reasons: [reason],
        verdict: grounding.verdict,
        grounding_result: grounding
      )
    end

    comparison = snap.current_eligibility_comparison
    unless comparison.eligible?
      return Decision.new(
        publishable: false,
        status: :stale_version_lock,
        errors: comparison.mismatches,
        reasons: comparison.stale_reasons.presence || [:stale_evidence],
        verdict: "stale",
        grounding_result: grounding,
        eligibility_comparison: comparison
      )
    end

    Decision.new(
      publishable: true,
      status: :publishable,
      errors: [],
      reasons: [],
      verdict: grounding.verdict,
      grounding_result: grounding,
      eligibility_comparison: comparison
    )
  end
end
