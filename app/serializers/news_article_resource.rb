# frozen_string_literal: true

# @lat: [[news-article-evidence#Changes after publication]]
class NewsArticleResource < ApplicationResource
  attributes :id, :match_kind

  attribute :title do |record|
    record.news_article&.title
  end

  attribute :url do |record|
    record.news_article&.canonical_url
  end

  attribute :outlet_name do |record|
    record.news_article&.outlet_name
  end

  attribute :author_name do |record|
    record.news_article&.author_name
  end

  attribute :published_at do |record|
    record.news_article&.published_at&.iso8601
  end

  attribute :article_kind do |record|
    record.news_article&.article_kind
  end
end
