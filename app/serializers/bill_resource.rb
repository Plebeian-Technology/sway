# frozen_string_literal: true

# @lat: [[news-article-evidence#Changes after publication]]
class BillResource < ApplicationResource
  # @lat: [[system-shape#System shape#One process, two languages#The bill page composes a page payload from several contracts]]
  def self.page_props(bill, current_user:, current_sway_locale:, district_legislator_names: false)
    BillPageResource.new(
      bill,
      params: {current_user:, current_sway_locale:, district_legislator_names:}
    ).serializable_hash.transform_keys(&:to_sym)
  end

  attributes :id,
    :external_id,
    :external_version,
    :title,
    :summary,
    :link,
    :chamber,
    :category,
    :status,
    :active,
    :scheduled_release_date_utc,
    :audio_bucket_path,
    :audio_by_line,
    :vote_date_time_utc,
    :introduced_date_time_utc,
    :house_vote_date_time_utc,
    :senate_vote_date_time_utc,
    :legislator_id,
    :sway_locale_id,
    :created_at

  attribute :summary_ai_unreviewed do |bill|
    bill.summary_ai_unreviewed?
  end

  attribute :vote do |bill|
    # @lat: [[system-shape#System shape#One process, two languages#The bill page composes a page payload from several contracts]]
    bill.vote && RollCallResource.new(bill.vote).serializable_hash
  end

  attribute :categories do |bill|
    bill.categories.select(&:active?).map(&:name)
  end

  many :related_articles, resource: NewsArticleResource
  many :news_testimonies, resource: NewsArticleTestimonyResource
end
