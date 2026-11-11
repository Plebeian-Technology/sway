# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_news_articles
# Database name: primary
#
#  id                      :integer          not null, primary key
#  approved                :boolean          default(FALSE), not null
#  approved_at             :datetime
#  match_evidence          :text
#  match_kind              :string           default("direct"), not null
#  review_version          :integer          default(0), not null
#  stance                  :string
#  stance_version          :integer          default(0), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  approved_by_id          :integer
#  bill_id                 :integer          not null
#  current_text_version_id :integer
#  news_article_id         :integer          not null
#  stance_by_id            :integer
#
# Indexes
#
#  index_bill_news_articles_on_approved_by_id               (approved_by_id)
#  index_bill_news_articles_on_bill_id                      (bill_id)
#  index_bill_news_articles_on_bill_id_and_approved         (bill_id,approved)
#  index_bill_news_articles_on_bill_id_and_news_article_id  (bill_id,news_article_id) UNIQUE
#  index_bill_news_articles_on_current_text_version_id      (current_text_version_id)
#  index_bill_news_articles_on_news_article_id              (news_article_id)
#  index_bill_news_articles_on_stance_by_id                 (stance_by_id)
#
# Foreign Keys
#
#  approved_by_id           (approved_by_id => users.id)
#  bill_id                  (bill_id => bills.id) ON DELETE => cascade
#  current_text_version_id  (current_text_version_id => news_article_text_versions.id) ON DELETE => restrict
#  news_article_id          (news_article_id => news_articles.id) ON DELETE => restrict
#  stance_by_id             (stance_by_id => users.id)
#
class BillNewsArticle < ApplicationRecord
  # @lat: [[news-article-evidence#Article identity and bill association]]
  MATCH_KINDS = %w[direct context].freeze
  STANCES = %w[support oppose].freeze

  belongs_to :bill, inverse_of: :bill_news_articles
  belongs_to :news_article, inverse_of: :bill_news_articles
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :stance_by, class_name: "User", optional: true
  belongs_to :current_text_version, class_name: "NewsArticleTextVersion", optional: true
  has_many :source_uses, class_name: "NewsArticleSourceUse", dependent: :restrict_with_error, inverse_of: :bill_news_article
  has_many :news_article_source_uses, class_name: "NewsArticleSourceUse", dependent: :restrict_with_error, inverse_of: :bill_news_article
  has_many :news_article_testimonies, dependent: :destroy, inverse_of: :bill_news_article

  before_destroy :reload_source_uses_if_loaded, prepend: true

  delegate :sway_locale, :legislative_session, to: :bill, allow_nil: true

  validates :news_article_id, uniqueness: {scope: :bill_id}
  validates :match_kind, presence: true, inclusion: {in: MATCH_KINDS}
  validates :stance, inclusion: {in: STANCES}, allow_nil: true
  validates :review_version, :stance_version, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validate :prevent_cross_bill_reassignment, on: :update
  validate :current_text_version_belongs_to_article

  scope :approved, -> { where(approved: true) }
  scope :unapproved, -> { where(approved: false) }
  scope :with_stance, -> { where.not(stance: nil) }
  scope :supporting, -> { where(stance: "support") }
  scope :opposing, -> { where(stance: "oppose") }
  scope :direct_matches, -> { where(match_kind: "direct") }
  scope :context_matches, -> { where(match_kind: "context") }
  scope :eligible_for_link, -> { approved }
  scope :eligible_for_synthesis, lambda {
    approved
      .joins(:current_text_version)
      .where(news_article_text_versions: {extraction_status: "extracted"})
      .where("LENGTH(TRIM(news_article_text_versions.text, ?)) > 0", " \t\r\n")
  }
  scope :eligible_for_testimony, lambda {
    approved
      .with_stance
      .joins(:news_article, :current_text_version)
      .where(news_articles: {article_kind: %w[op_ed editorial]})
      .where(news_article_text_versions: {extraction_status: "extracted"})
      .where("LENGTH(TRIM(news_article_text_versions.text, ?)) > 0", " \t\r\n")
  }

  class << self
    alias_method :support, :supporting
    alias_method :oppose, :opposing
    alias_method :direct_match, :direct_matches
    alias_method :context_match, :context_matches
    alias_method :link_eligible, :eligible_for_link
    alias_method :synthesis_eligible, :eligible_for_synthesis
    alias_method :testimony_eligible, :eligible_for_testimony
  end

  def approve!(by:)
    update!(
      approved: true,
      approved_by: by,
      approved_at: Time.current,
      review_version: review_version + 1
    )
    self
  end

  def withdraw_approval!(by:)
    update!(
      approved: false,
      approved_by: by,
      review_version: review_version + 1
    )
    self
  end

  def set_stance!(new_stance, by:)
    stance_str = new_stance.to_s
    raise ArgumentError, "Invalid stance: #{new_stance}" unless STANCES.include?(stance_str)

    update!(
      stance: stance_str,
      stance_by: by,
      stance_version: stance_version + 1
    )
    self
  end

  def clear_stance!(by:)
    update!(
      stance: nil,
      stance_by: by,
      stance_version: stance_version + 1
    )
    self
  end

  def eligible_for_link?
    approved?
  end
  alias_method :link_eligible?, :eligible_for_link?

  def eligible_for_synthesis?
    approved? && current_text_version&.usable_text? == true
  end
  alias_method :synthesis_eligible?, :eligible_for_synthesis?

  def eligible_for_testimony?
    approved? &&
      stance.present? &&
      current_text_version&.usable_text? == true &&
      %w[op_ed editorial].include?(news_article&.article_kind)
  end
  alias_method :testimony_eligible?, :eligible_for_testimony?

  private

  def prevent_cross_bill_reassignment
    errors.add(:bill_id, "cannot be changed once persisted") if bill_id_changed?
  end

  def current_text_version_belongs_to_article
    return if current_text_version_id.blank?

    if current_text_version&.news_article_id != news_article_id
      errors.add(:current_text_version, "must belong to the associated news article")
    end
  end

  def reload_source_uses_if_loaded
    source_uses.reset if association(:source_uses).loaded?
    news_article_source_uses.reset if association(:news_article_source_uses).loaded?
  end
end
