# frozen_string_literal: true

require "uri"

# @lat: [[news-article-evidence#Article identity and bill association]]
class AdminBillNewsArticleResource < ApplicationResource
  attributes :id,
    :bill_id,
    :news_article_id,
    :approved,
    :review_version,
    :stance,
    :stance_version,
    :current_text_version_id,
    :match_kind

  attribute :article_kind do |record|
    record.news_article&.article_kind
  end

  attribute :url do |record|
    record.news_article&.canonical_url
  end

  attribute :title do |record|
    record.news_article&.title
  end

  attribute :source_name do |record|
    record.news_article&.outlet_name
  end

  attribute :domain do |record|
    url = record.news_article&.canonical_url
    if url.present?
      URI.parse(url).host.to_s.downcase.sub(/\Awww\./, "").presence
    end
  rescue URI::InvalidURIError
    nil
  end

  attribute :author do |record|
    record.news_article&.author_name
  end

  attribute :published_at do |record|
    record.news_article&.published_at&.iso8601
  end

  attribute :has_text do |record|
    record.current_text_version&.usable_text? == true
  end

  attribute :text_digest do |record|
    record.current_text_version&.digest
  end

  attribute :text_origin do |record|
    record.current_text_version&.origin
  end

  attribute :excerpt do |record|
    text = record.current_text_version&.text
    text.present? ? text[0, 300] : nil
  end

  attribute :created_at do |record|
    record.created_at&.iso8601
  end

  attribute :updated_at do |record|
    record.updated_at&.iso8601
  end
end
