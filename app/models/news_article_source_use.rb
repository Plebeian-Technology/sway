# frozen_string_literal: true

# @lat: [[news-article-evidence#Source snapshots and claim uses]]
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
class NewsArticleSourceUse < ApplicationRecord
  GROUNDING_STATUSES = %w[pending supported unsupported indeterminate].freeze

  alias_attribute :verbatim_excerpt, :evidence_excerpt
  alias_attribute :grounding_verdict, :grounding_status

  belongs_to :news_article_source_snapshot, class_name: "NewsArticleSourceSnapshot", inverse_of: :news_article_source_uses
  belongs_to :bill_news_article, class_name: "BillNewsArticle", inverse_of: :news_article_source_uses
  belongs_to :text_version, class_name: "NewsArticleTextVersion", inverse_of: :news_article_source_uses

  has_one :bill, through: :news_article_source_snapshot
  has_one :news_article, through: :bill_news_article

  alias_method :snapshot, :news_article_source_snapshot
  alias_method :snapshot=, :news_article_source_snapshot=

  validates :claim_text, presence: true
  validates :evidence_excerpt, presence: true
  validates :citation_url, presence: true
  validates :grounding_status, presence: true, inclusion: {in: GROUNDING_STATUSES}
  validate :validate_cross_bill_isolation
  validate :validate_cross_article_isolation
  validate :validate_verbatim_excerpt_in_text

  before_update :prevent_mutation
  before_destroy :prevent_mutation, prepend: true

  scope :supported, -> { where(grounding_status: "supported") }
  scope :unsupported, -> { where(grounding_status: "unsupported") }
  scope :indeterminate, -> { where(grounding_status: "indeterminate") }
  scope :pending, -> { where(grounding_status: "pending") }

  def readonly?
    persisted?
  end

  private

  def validate_cross_bill_isolation
    return if bill_news_article.nil? || news_article_source_snapshot.nil?

    if bill_news_article.bill_id != news_article_source_snapshot.bill_id
      errors.add(:bill_news_article, "must belong to the snapshot's bill")
    end
  end

  def validate_cross_article_isolation
    return if text_version.nil? || bill_news_article.nil?

    if text_version.news_article_id != bill_news_article.news_article_id
      errors.add(:text_version, "must belong to the associated bill news article")
    end
  end

  def validate_verbatim_excerpt_in_text
    return if evidence_excerpt.blank? || text_version.nil?

    text_content = text_version.text.to_s
    unless text_content.include?(evidence_excerpt)
      errors.add(:evidence_excerpt, "must appear verbatim in the referenced text version")
    end
  end

  def prevent_mutation
    raise ActiveRecord::ReadOnlyRecord, "NewsArticleSourceUse records are immutable"
  end
end
