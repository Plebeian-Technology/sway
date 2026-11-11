# frozen_string_literal: true

# @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
class SummarySourcesRecordResource < ApplicationResource
  attributes :source_chars, :source_cap, :source_reached_chars, :source_truncated, :extracted_text_chars,
    :diff_target, :diff_sections_modified, :diff_sections_referenced, :diff_sections_not_found,
    :citation_keys_offered, :citation_keys_total, :citation_sample_titles,
    :news_search_available, :newsroom_domains, :news_articles_offered, :news_articles_total, :news_articles

  attribute :source_kind do |record|
    record.source_kind.to_s
  end

  attribute :diff_generated_at do |record|
    record.diff_generated_at&.iso8601
  end

  attribute :news_fetched_at do |record|
    record.news_fetched_at&.iso8601
  end
end
