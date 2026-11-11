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
class NewsArticle < ApplicationRecord
  # @lat: [[news-article-evidence#Article identity and bill association]]
  ARTICLE_KINDS = %w[reporting op_ed editorial unknown].freeze

  alias_attribute :url, :canonical_url

  has_many :bill_news_articles, inverse_of: :news_article, dependent: :restrict_with_error
  has_many :bills, through: :bill_news_articles
  has_many :text_versions, class_name: "NewsArticleTextVersion", inverse_of: :news_article, dependent: :restrict_with_error

  validates :canonical_url, presence: true, uniqueness: true
  validates :title, :outlet_name, presence: true
  validates :article_kind, presence: true, inclusion: {in: ARTICLE_KINDS}
  validate :validate_canonical_url_format

  private

  def validate_canonical_url_format
    return if canonical_url.blank?

    uri = URI.parse(canonical_url)
    errors.add(:canonical_url, "must be a valid HTTPS URL") unless uri.is_a?(URI::HTTPS) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:canonical_url, "must be a valid HTTPS URL")
  end
end
