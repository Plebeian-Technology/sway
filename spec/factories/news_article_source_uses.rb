# frozen_string_literal: true

# == Schema Information
#
# Table name: news_article_source_uses
# Database name: primary
#
#  id                              :integer          not null, primary key
#  citation_url                    :string           not null
#  claim_text                      :text             not null
#  evidence_excerpt                :text             not null
#  grounding_reason                :text
#  grounding_status                :string           default("pending"), not null
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  bill_news_article_id            :integer          not null
#  news_article_source_snapshot_id :integer          not null
#  text_version_id                 :integer          not null
#
# Indexes
#
#  idx_on_news_article_source_snapshot_id_400dbd1ea3       (news_article_source_snapshot_id)
#  index_news_article_source_uses_on_bill_news_article_id  (bill_news_article_id)
#  index_news_article_source_uses_on_text_version_id       (text_version_id)
#  index_source_uses_on_bill_news_article_id               (bill_news_article_id)
#  index_source_uses_on_snapshot_and_status                (news_article_source_snapshot_id,grounding_status)
#  index_source_uses_on_snapshot_id                        (news_article_source_snapshot_id)
#  index_source_uses_on_text_version_id                    (text_version_id)
#
# Foreign Keys
#
#  bill_news_article_id             (bill_news_article_id => bill_news_articles.id) ON DELETE => restrict
#  news_article_source_snapshot_id  (news_article_source_snapshot_id => news_article_source_snapshots.id) ON DELETE => cascade
#  text_version_id                  (text_version_id => news_article_text_versions.id) ON DELETE => restrict
#
FactoryBot.define do
  factory :news_article_source_use do
    news_article_source_snapshot
    bill_news_article { association :bill_news_article, :approved, :with_text_version, bill: news_article_source_snapshot.bill }
    text_version { bill_news_article.current_text_version }
    claim_text { "Council passed the housing density amendment unanimously." }
    evidence_excerpt { text_version.text.to_s.truncate(40, omission: "") }
    citation_url { bill_news_article.news_article.canonical_url }
    grounding_status { "pending" }
    grounding_reason { nil }

    trait :supported do
      grounding_status { "supported" }
      grounding_reason { "Claim directly corroborated by verbatim excerpt." }
    end

    trait :unsupported do
      grounding_status { "unsupported" }
      grounding_reason { "Claim contradicts source reporting." }
    end

    trait :indeterminate do
      grounding_status { "indeterminate" }
      grounding_reason { "Model unable to verify claim against excerpt." }
    end
  end
end
