# frozen_string_literal: true

# == Schema Information
#
# Table name: news_article_text_versions
# Database name: primary
#
#  id                :integer          not null, primary key
#  digest            :string           not null
#  extraction_status :string           default("extracted"), not null
#  final_url         :string
#  origin            :string           default("retrieved"), not null
#  requested_url     :string
#  text              :text
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  actor_id          :integer
#  news_article_id   :integer          not null
#
# Indexes
#
#  idx_on_news_article_id_created_at_fd5f7ee9a7                    (news_article_id,created_at)
#  index_news_article_text_versions_on_actor_id                    (actor_id)
#  index_news_article_text_versions_on_digest                      (digest)
#  index_news_article_text_versions_on_news_article_id             (news_article_id)
#  index_news_article_text_versions_on_news_article_id_and_digest  (news_article_id,digest)
#
# Foreign Keys
#
#  actor_id         (actor_id => users.id)
#  news_article_id  (news_article_id => news_articles.id) ON DELETE => restrict
#
FactoryBot.define do
  factory :news_article_text_version do
    news_article
    add_attribute(:text) { "Full article reporting on city council legislative proceedings with verbatim testimony." }
    add_attribute(:digest) { |v| Digest::SHA256.hexdigest(v.text.to_s) if v.text.present? }
    add_attribute(:origin) { "retrieved" }
    add_attribute(:extraction_status) { "extracted" }
    add_attribute(:requested_url) { "https://thebaltimorebanner.com/community/article-1" }
    add_attribute(:final_url) { "https://thebaltimorebanner.com/community/article-1" }

    trait :retrieved do
      add_attribute(:origin) { "retrieved" }
      actor { nil }
    end

    trait :manual do
      add_attribute(:origin) { "manual" }
      actor { association :user, :sway_admin }
      add_attribute(:requested_url) { nil }
      add_attribute(:final_url) { nil }
    end

    trait :admin do
      add_attribute(:origin) { "admin" }
      actor { association :user, :sway_admin }
      add_attribute(:requested_url) { nil }
      add_attribute(:final_url) { nil }
    end

    trait :extracted do
      add_attribute(:extraction_status) { "extracted" }
      add_attribute(:text) { "Full article reporting on city council legislative proceedings with verbatim testimony." }
    end

    trait :paywalled do
      add_attribute(:text) { nil }
      add_attribute(:digest) { nil }
      add_attribute(:extraction_status) { "paywalled" }
    end

    trait :failed do
      add_attribute(:text) { nil }
      add_attribute(:digest) { nil }
      add_attribute(:extraction_status) { "failed" }
    end
  end
end
