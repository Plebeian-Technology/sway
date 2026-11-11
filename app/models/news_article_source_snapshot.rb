# frozen_string_literal: true

# @lat: [[news-article-evidence#Source snapshots and claim uses]]
# == Schema Information
#
# Table name: news_article_source_snapshots
# Database name: primary
#
#  id             :integer          not null, primary key
#  digest         :string           not null
#  purpose        :string           not null
#  run_receipt    :string
#  source_entries :json             not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  actor_id       :integer
#  bill_id        :integer          not null
#
# Indexes
#
#  index_news_article_source_snapshots_on_actor_id                (actor_id)
#  index_news_article_source_snapshots_on_bill_id                 (bill_id)
#  index_news_article_source_snapshots_on_bill_id_and_created_at  (bill_id,created_at)
#  index_news_article_source_snapshots_on_bill_id_and_purpose     (bill_id,purpose)
#  index_news_article_source_snapshots_on_digest                  (digest)
#  index_news_article_source_snapshots_on_run_receipt             (run_receipt)
#
# Foreign Keys
#
#  actor_id  (actor_id => users.id) ON DELETE => nullify
#  bill_id   (bill_id => bills.id) ON DELETE => cascade
#
class NewsArticleSourceSnapshot < ApplicationRecord
  PURPOSES = %w[summary testimony].freeze

  belongs_to :bill, inverse_of: :news_article_source_snapshots
  belongs_to :actor, class_name: "User", optional: true
  has_many :source_uses, class_name: "NewsArticleSourceUse", dependent: :delete_all, inverse_of: :news_article_source_snapshot
  has_many :news_article_source_uses, class_name: "NewsArticleSourceUse", dependent: :delete_all, inverse_of: :news_article_source_snapshot
  has_many :bill_summary_revisions, foreign_key: :news_source_snapshot_id, dependent: :nullify, inverse_of: :news_source_snapshot
  has_many :news_article_testimonies, dependent: :nullify, inverse_of: :news_article_source_snapshot

  validates :purpose, presence: true, inclusion: {in: PURPOSES}
  validates :digest, presence: true, format: {with: /\A[a-f0-9]{64}\z/i}
  validate :validate_source_entries_belong_to_bill

  before_validation :compute_digest
  before_update :prevent_mutation
  before_destroy :prevent_mutation, prepend: true

  scope :for_summary, -> { where(purpose: "summary") }
  scope :for_testimony, -> { where(purpose: "testimony") }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def readonly?
    persisted?
  end

  def summary?
    purpose == "summary"
  end

  def testimony?
    purpose == "testimony"
  end

  def captured_source_entries
    source_entries || []
  end

  def captured_text_version_ids
    (source_entries || []).filter_map do |entry|
      h = entry.respond_to?(:to_h) ? entry.to_h.stringify_keys : entry
      (h["text_version_id"] || h["news_article_text_version_id"])&.to_i
    end.reject(&:zero?).uniq
  end

  def captured_text_versions
    NewsArticleTextVersion.where(id: captured_text_version_ids)
  end

  def current_eligibility_comparison
    mismatches = []
    stale_reasons = []
    details = []

    (source_entries || []).each do |entry|
      h = entry.respond_to?(:to_h) ? entry.to_h.stringify_keys : entry
      bna_id = h["bill_news_article_id"]&.to_i
      bna = bill.bill_news_articles.find_by(id: bna_id)

      if bna.nil?
        stale_reasons << :association_missing
        mismatches << "Bill news article #{bna_id} not found on bill"
        details << {bill_news_article_id: bna_id, status: :association_missing}
        next
      end

      entry_stale = []
      unless bna.approved?
        entry_stale << :approval_withdrawn
        mismatches << "Bill news article #{bna_id} approval has been withdrawn"
      end

      captured_tv_id = (h["text_version_id"] || h["news_article_text_version_id"])&.to_i
      if bna.current_text_version_id != captured_tv_id
        entry_stale << :text_version_replaced
        mismatches << "Bill news article #{bna_id} selected text version changed from #{captured_tv_id} to #{bna.current_text_version_id}"
      end

      captured_review_version = h["review_version"]&.to_i
      if captured_review_version && bna.review_version != captured_review_version
        entry_stale << :review_version_mismatch
        mismatches << "Bill news article #{bna_id} review version changed from #{captured_review_version} to #{bna.review_version}"
      end

      captured_stance = h["stance"]
      captured_stance_version = h["stance_version"]&.to_i
      if (captured_stance && bna.stance != captured_stance) || (captured_stance_version && bna.stance_version != captured_stance_version)
        entry_stale << :stance_changed
        mismatches << "Bill news article #{bna_id} stance changed from #{captured_stance} to #{bna.stance}"
      end

      if entry_stale.empty?
        details << {bill_news_article_id: bna_id, status: :current}
      else
        stale_reasons.concat(entry_stale)
        details << {bill_news_article_id: bna_id, status: entry_stale.first, reasons: entry_stale}
      end
    end

    stale_reasons.uniq!
    eligible = mismatches.empty?

    EligibilityComparison.new(
      eligible: eligible,
      mismatches: mismatches,
      stale_reasons: stale_reasons,
      details: details
    )
  end
  alias_method :check_current_eligibility, :current_eligibility_comparison
  alias_method :compare_current_eligibility, :current_eligibility_comparison

  def current_eligibility_matches?
    current_eligibility_comparison.eligible?
  end

  private

  def compute_digest
    return if digest.present?

    normalized_entries = (source_entries || []).map do |e|
      e = e.respond_to?(:to_h) ? e.to_h.stringify_keys : e
      e.transform_keys(&:to_s)
    end.sort_by { |e| e["bill_news_article_id"].to_i }

    payload = {
      bill_id: bill_id,
      purpose: purpose.to_s,
      run_receipt: run_receipt,
      actor_id: actor_id,
      source_entries: normalized_entries
    }.to_json

    self.digest = Digest::SHA256.hexdigest(payload)
  end

  def validate_source_entries_belong_to_bill
    return if bill_id.blank? || source_entries.blank?

    bna_ids = (source_entries || []).filter_map do |entry|
      h = entry.respond_to?(:to_h) ? entry.to_h.stringify_keys : entry
      h["bill_news_article_id"]&.to_i
    end.reject(&:zero?).uniq

    return if bna_ids.empty?

    foreign_count = BillNewsArticle.where(id: bna_ids).where.not(bill_id: bill_id).count
    if foreign_count.positive?
      errors.add(:source_entries, "contains entries from a different bill")
    end
  end

  def prevent_mutation
    raise ActiveRecord::ReadOnlyRecord, "NewsArticleSourceSnapshot records are immutable"
  end

  class EligibilityComparison
    attr_reader :eligible, :mismatches, :stale_reasons, :details

    def initialize(eligible:, mismatches: [], stale_reasons: [], details: [])
      @eligible = eligible
      @mismatches = mismatches
      @stale_reasons = stale_reasons
      @details = details
    end

    def eligible?
      @eligible
    end

    def matches?
      @eligible
    end
  end
end
