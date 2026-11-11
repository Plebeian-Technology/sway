# frozen_string_literal: true

# == Schema Information
#
# Table name: news_articles
# Database name: primary
#
#  id            :integer          not null, primary key
#  article_kind  :string           default("unknown"), not null
#  author_name   :string
#  canonical_url :string           not null
#  outlet_name   :string           not null
#  published_at  :datetime
#  title         :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_news_articles_on_canonical_url  (canonical_url) UNIQUE
#  index_news_articles_on_outlet_name    (outlet_name)
#  index_news_articles_on_published_at   (published_at)
#
FactoryBot.define do
  factory :news_article do
    sequence(:canonical_url) { |n| "https://thebaltimorebanner.com/community/article-#{n}" }
    title { "City Council Considers Housing Legislation" }
    add_attribute(:outlet_name) { "The Baltimore Banner" }
    add_attribute(:author_name) { "Jane Reporter" }
    add_attribute(:published_at) { 1.day.ago }
    add_attribute(:article_kind) { "reporting" }

    trait :op_ed do
      add_attribute(:article_kind) { "op_ed" }
    end

    trait :editorial do
      add_attribute(:article_kind) { "editorial" }
    end

    trait :unknown do
      add_attribute(:article_kind) { "unknown" }
    end
  end
end
