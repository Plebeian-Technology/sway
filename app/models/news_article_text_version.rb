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
class NewsArticleTextVersion < ApplicationRecord
  # @lat: [[news-article-evidence#Immutable article text]]
  ORIGINS = %w[retrieved manual admin].freeze
  EXTRACTION_STATUSES = %w[extracted paywalled failed].freeze

  belongs_to :news_article, inverse_of: :text_versions
  belongs_to :actor, class_name: "User", optional: true
  has_many :bill_news_articles, foreign_key: :current_text_version_id, dependent: :restrict_with_error, inverse_of: :current_text_version
  has_many :source_uses, class_name: "NewsArticleSourceUse", foreign_key: :text_version_id, dependent: :restrict_with_error, inverse_of: :text_version
  has_many :news_article_source_uses, class_name: "NewsArticleSourceUse", foreign_key: :text_version_id, dependent: :restrict_with_error, inverse_of: :text_version
  has_many :news_article_testimonies, dependent: :restrict_with_error, inverse_of: :news_article_text_version

  validates :origin, presence: true, inclusion: {in: ORIGINS}
  validates :extraction_status, presence: true, inclusion: {in: EXTRACTION_STATUSES}
  validates :text, presence: true, if: :text_required?
  validates :digest, presence: true, format: {with: /\A[a-f0-9]{64}\z/i}

  before_validation :compute_digest
  before_update :prevent_mutation
  before_destroy :prevent_mutation, prepend: true

  scope :extracted, -> { where(extraction_status: "extracted") }
  scope :paywalled, -> { where(extraction_status: "paywalled") }
  scope :failed, -> { where(extraction_status: "failed") }
  scope :retrieved, -> { where(origin: "retrieved") }
  scope :manual, -> { where(origin: "manual") }
  scope :admin, -> { where(origin: "admin") }

  def readonly?
    persisted?
  end

  def retrieved?
    origin == "retrieved"
  end

  def manual?
    origin == "manual"
  end

  def admin?
    origin == "admin"
  end

  def extracted?
    extraction_status == "extracted"
  end

  def paywalled?
    extraction_status == "paywalled"
  end

  def failed?
    extraction_status == "failed"
  end

  def usable_text?
    extracted? && text.present?
  end

  private

  def compute_digest
    t = text
    if !t.nil?
      self.digest = Digest::SHA256.hexdigest(t)
    elsif digest.blank?
      self.digest = Digest::SHA256.hexdigest("")
    end
  end

  def text_required?
    extracted? || manual?
  end

  def prevent_mutation
    raise ActiveRecord::ReadOnlyRecord, "NewsArticleTextVersion records are immutable"
  end
end
