# frozen_string_literal: true

# @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#The persist guard is extracted so a batch ingest can call it directly]]
# @lat: [[news-gate#Why ungrounded generations are quarantined as draft revisions]]
class SummaryRunPersistGuard
  def self.call(bill, provisioning, attrs, evidence_digest: nil, news_source_snapshot: nil, grounding_result: nil)
    snapshot = news_source_snapshot || attrs.delete(:news_source_snapshot)
    snapshot_id = snapshot.is_a?(NewsArticleSourceSnapshot) ? snapshot.id : (snapshot || attrs.delete(:news_source_snapshot_id))
    snapshot_record = if snapshot.is_a?(NewsArticleSourceSnapshot)
      snapshot
    elsif snapshot_id
      NewsArticleSourceSnapshot.find_by(id: snapshot_id)
    end
    raw_usage = if attrs.key?(:news_usage)
      attrs.delete(:news_usage)
    elsif snapshot_id.present?
      "cited"
    else
      "none"
    end
    news_usage = raw_usage

    outcome = bill.with_lock do
      SummaryRunLock.settle_under_lock(provisioning) do
        if SummaryRunMarker.operator_paste?(provisioning.summary_run_id)
          :superseded
        elsif evidence_digest && provisioning.testimony_digest != evidence_digest
          :evidence_withdrawn
        else
          previous_draft = provisioning.llm_summary

          BillSummaryRevision.ensure_baseline!(bill, provisioning: provisioning)

          published = false
          if attrs.key?(:llm_summary) && attrs[:llm_summary].present?
            published, decision = publish_summary!(
              bill,
              attrs,
              previous_draft,
              news_usage: news_usage,
              snapshot: snapshot_record,
              grounding_result: grounding_result
            )

            if published
              attrs[:generation_error] = nil
            elsif decision&.errors&.any? && decision.status != :operator_overwrite
              attrs[:generation_error] = decision.errors.join("; ")
            end
          end

          provisioning.update!(attrs)

          if attrs.key?(:llm_summary) && attrs[:llm_summary].present?
            role = published ? "published" : "draft"
            BillSummaryRevision.record_revision!(
              bill: bill,
              summary_markdown: attrs[:llm_summary],
              origin: "model_generation",
              publication_role: role,
              review_state: "unreviewed",
              llm_provider: attrs[:llm_provider] || provisioning.llm_provider,
              llm_model: attrs[:llm_model] || provisioning.llm_model,
              news_source_snapshot: snapshot_id
            )
          end

          :persisted
        end
      end
    end

    case outcome
    when :evidence_withdrawn then :evidence_withdrawn
    when :superseded then :superseded
    when nil then :vanished
    else
      :persisted
    end
  end

  def self.publish_summary!(bill, attrs, previous_draft, news_usage: nil, snapshot: nil, grounding_result: nil)
    return [false, nil] unless attrs.key?(:llm_summary)

    summary = attrs[:llm_summary]
    return [false, nil] if summary.blank?

    decision = BillSummaryPublication.evaluate(
      bill: bill,
      previous_draft: previous_draft,
      content: summary,
      news_usage: news_usage,
      snapshot: snapshot,
      grounding_result: grounding_result
    )

    if decision.publishable?
      bill.update_columns(summary: summary, updated_at: Time.current)
      SwayLogging.info(
        "generate_bill_summary.published",
        bill_id: bill.id,
        message: "the new summary was published to the bill page; it carries the unreviewed notice " \
          "until a person revises it"
      )
      [true, decision]
    else
      if decision.status == :operator_overwrite
        SwayLogging.info(
          "generate_bill_summary.publish_declined",
          bill_id: bill.id,
          message: "the published summary is neither empty, the placeholder, nor the draft this run " \
            "replaced — a person wrote it, so the new summary stays a draft"
        )
      elsif decision.errors.any?
        SwayLogging.warn(
          "generate_bill_summary.publish_declined_grounding",
          bill_id: bill.id,
          status: decision.status,
          errors: decision.errors
        )
      end
      [false, decision]
    end
  end
  private_class_method :publish_summary!
end
