# frozen_string_literal: true

# == Schema Information
#
# Table name: llm_bill_summarization_instructions
# Database name: primary
#
#  id                      :integer          not null, primary key
#  last_seeded_at          :datetime
#  legislative_body_makeup :text
#  news_media_website_urls :json             not null
#  worked_example          :text
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  sway_locale_id          :integer          not null
#
# Indexes
#
#  index_llm_bill_summarization_instructions_on_sway_locale_id  (sway_locale_id) UNIQUE
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
class LlmBillSummarizationInstruction < ApplicationRecord
  # @lat: [[news-source-configuration#News source configuration contract]]
  belongs_to :sway_locale

  validates :sway_locale_id, uniqueness: true

  def news_sources
    doc = resolve_locale_document
    return doc.news_sources if doc

    (news_media_website_urls || []).map do |url|
      {"url" => SwayLocale::DocumentReader.normalize_news_source_url(url), "path_policy" => "search_hint"}
    end
  end

  def source_config_digest
    doc = resolve_locale_document
    doc&.source_config_digest
  end

  def allowed_domains
    urls = news_sources.pluck("url")
    Llm::AllowedDomain.filter_list(urls)
  end

  private

  def resolve_locale_document
    return nil unless sway_locale

    SwayLocale::DocumentReader.current_for(sway_locale.name)
  rescue KeyError
    SwayLocale::DocumentReader.find(sway_locale.name)
  end
end
