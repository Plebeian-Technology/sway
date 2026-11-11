# frozen_string_literal: true

# @lat: [[bill-creator-summary-tab#Planned recoverable summary history]]
class BillSummaryRevisionResource < ApplicationResource
  attributes :id,
    :bill_id,
    :summary_markdown,
    :origin,
    :llm_provider,
    :llm_model,
    :publication_role,
    :review_state,
    :restored_from_id,
    :news_source_snapshot_id,
    :created_at

  attribute :actor_name do |revision|
    revision.actor_name
  end

  attribute :has_snapshot do |revision|
    revision.news_source_snapshot_id.present?
  end
end
