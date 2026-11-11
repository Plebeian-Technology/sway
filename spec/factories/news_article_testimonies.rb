# frozen_string_literal: true

# == Schema Information
#
# Table name: news_article_testimonies
# Database name: primary
#
#  id                              :integer          not null, primary key
#  argument_markdown               :text             not null
#  author_name                     :string
#  citation_url                    :string           not null
#  evidence_excerpt                :text             not null
#  outlet_name                     :string           not null
#  publication_state               :string           default("draft"), not null
#  published_at                    :datetime
#  review_version                  :integer          default(0), not null
#  stance                          :string           not null
#  stance_version                  :integer          default(0), not null
#  text_digest                     :string           not null
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  bill_news_article_id            :integer          not null
#  news_article_source_snapshot_id :integer
#  news_article_text_version_id    :integer          not null
#
# Indexes
#
#  idx_news_testimonies_on_bna_and_pub_state               (bill_news_article_id,publication_state)
#  idx_news_testimonies_on_snapshot_id                     (news_article_source_snapshot_id)
#  idx_news_testimonies_on_text_version_id                 (news_article_text_version_id)
#  index_news_article_testimonies_on_bill_news_article_id  (bill_news_article_id)
#
# Foreign Keys
#
#  bill_news_article_id             (bill_news_article_id => bill_news_articles.id) ON DELETE => cascade
#  news_article_source_snapshot_id  (news_article_source_snapshot_id => news_article_source_snapshots.id) ON DELETE => nullify
#  news_article_text_version_id     (news_article_text_version_id => news_article_text_versions.id) ON DELETE => restrict
#
FactoryBot.define do
  factory :news_article_testimony do
    bill_news_article
    news_article_source_snapshot { nil }
    news_article_text_version do
      bill_news_article.current_text_version || association(:news_article_text_version, news_article: bill_news_article.news_article)
    end
    add_attribute(:argument_markdown) { "Council Bill 100 provides essential housing protections that strengthen tenant rights." }
    add_attribute(:evidence_excerpt) { news_article_text_version.text.to_s[0, 30] }
    add_attribute(:citation_url) { bill_news_article.news_article.canonical_url }
    add_attribute(:outlet_name) { bill_news_article.news_article.outlet_name }
    add_attribute(:author_name) { bill_news_article.news_article.author_name }
    add_attribute(:stance) { bill_news_article.stance || "support" }
    add_attribute(:stance_version) { bill_news_article.stance_version }
    add_attribute(:review_version) { bill_news_article.review_version }
    add_attribute(:text_digest) { news_article_text_version.digest }
    add_attribute(:publication_state) { "draft" }

    trait :published do
      add_attribute(:publication_state) { "published" }
      add_attribute(:published_at) { Time.current }
    end

    trait :support do
      add_attribute(:stance) { "support" }
    end

    trait :oppose do
      add_attribute(:stance) { "oppose" }
    end
  end
end
