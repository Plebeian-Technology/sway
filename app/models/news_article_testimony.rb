# frozen_string_literal: true

# @lat: [[news-testimony#Grounding published opinion testimony in article evidence]]
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
class NewsArticleTestimony < ApplicationRecord
  STANCES = %w[support oppose].freeze
  PUBLICATION_STATES = %w[draft published withdrawn].freeze

  alias_attribute :argument, :argument_markdown
  alias_attribute :url, :citation_url
  alias_attribute :canonical_url, :citation_url
  alias_attribute :status, :publication_state

  belongs_to :bill_news_article, inverse_of: :news_article_testimonies
  belongs_to :news_article_source_snapshot, class_name: "NewsArticleSourceSnapshot", optional: true, inverse_of: :news_article_testimonies
  belongs_to :news_article_text_version, class_name: "NewsArticleTextVersion", inverse_of: :news_article_testimonies

  has_one :bill, through: :bill_news_article
  has_one :news_article, through: :bill_news_article

  alias_method :snapshot, :news_article_source_snapshot
  alias_method :snapshot=, :news_article_source_snapshot=
  alias_method :text_version, :news_article_text_version
  alias_method :text_version=, :news_article_text_version=

  validates :argument_markdown, presence: true
  validates :evidence_excerpt, presence: true
  validates :outlet_name, :citation_url, presence: true
  validates :stance, presence: true, inclusion: {in: STANCES}
  validates :stance_version, :review_version, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validates :text_digest, presence: true
  validates :publication_state, presence: true, inclusion: {in: PUBLICATION_STATES}

  validate :validate_evidence_excerpt_in_text_version
  validate :validate_cross_bill_isolation
  validate :validate_text_version_belongs_to_article

  scope :drafts, -> { where(publication_state: "draft") }
  scope :published, -> { where(publication_state: "published") }
  scope :supporting, -> { where(stance: "support") }
  scope :opposing, -> { where(stance: "oppose") }

  def draft?
    publication_state == "draft"
  end

  def published?
    publication_state == "published"
  end

  def stale?(reload: true)
    bna = reload ? bill_news_article&.reload : bill_news_article
    return true if bna.nil? || !bna.approved?
    return true if bna.stance != stance
    return true if bna.stance_version != stance_version
    return true if bna.current_text_version_id != news_article_text_version_id
    return true if bna.current_text_version&.digest != text_digest
    return true if review_version.present? && bna.review_version != review_version

    false
  rescue ActiveRecord::RecordNotFound
    true
  end

  def currently_eligible?(reload: false)
    !stale?(reload: reload) && bill_news_article&.eligible_for_testimony? == true
  end

  private

  def validate_evidence_excerpt_in_text_version
    return if evidence_excerpt.blank? || news_article_text_version.nil?

    text_content = news_article_text_version.text.to_s
    unless text_content.include?(evidence_excerpt)
      errors.add(:evidence_excerpt, "must appear verbatim in the referenced text version")
    end
  end

  def validate_cross_bill_isolation
    snapshot = news_article_source_snapshot
    return if bill_news_article.nil? || snapshot.nil?

    if bill_news_article.bill_id != snapshot.bill_id
      errors.add(:bill_news_article, "must belong to the snapshot's bill")
    end
  end

  def validate_text_version_belongs_to_article
    return if news_article_text_version.nil? || bill_news_article.nil?

    if news_article_text_version.news_article_id != bill_news_article.news_article_id
      errors.add(:news_article_text_version, "must belong to the associated bill news article")
    end
  end
end
