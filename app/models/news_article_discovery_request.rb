# frozen_string_literal: true

# @lat: [[news-article-evidence#Discovery request receipt]]
# == Schema Information
#
# Table name: news_article_discovery_requests
# Database name: primary
#
#  id                   :integer          not null, primary key
#  completed_at         :datetime
#  diagnostics          :json             not null
#  match_counts         :json             not null
#  model                :string           not null
#  provider             :string           not null
#  query                :text
#  source_config_digest :string           not null
#  status               :string           default("queued"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  bill_id              :integer          not null
#  requested_by_id      :integer          not null
#
# Indexes
#
#  idx_on_bill_id_created_at_5965be0083                         (bill_id,created_at)
#  index_news_article_discovery_requests_on_bill_id             (bill_id)
#  index_news_article_discovery_requests_on_bill_id_and_status  (bill_id,status)
#  index_news_article_discovery_requests_on_requested_by_id     (requested_by_id)
#  index_news_article_discovery_requests_on_status              (status)
#
# Foreign Keys
#
#  bill_id          (bill_id => bills.id) ON DELETE => cascade
#  requested_by_id  (requested_by_id => users.id) ON DELETE => restrict
#
class NewsArticleDiscoveryRequest < ApplicationRecord
  STATUSES = %w[queued running succeeded no_matches partial_failure failed unsupported].freeze
  TERMINAL_STATUSES = %w[succeeded no_matches partial_failure failed unsupported].freeze

  belongs_to :bill, inverse_of: :news_article_discovery_requests
  belongs_to :requested_by, class_name: "User", inverse_of: :news_article_discovery_requests

  validates :status, presence: true, inclusion: {in: STATUSES}
  validates :source_config_digest, presence: true, format: {with: /\A[a-f0-9]{64}\z/}
  validates :provider, :model, presence: true
  validate :validate_requested_by_is_sway_admin

  scope :terminal, -> { where(status: TERMINAL_STATUSES) }
  scope :active, -> { where(status: %w[queued running]) }

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def succeeded?
    status == "succeeded"
  end

  def no_matches?
    status == "no_matches"
  end

  def unsupported?
    status == "unsupported"
  end

  def failed?
    status == "failed"
  end

  def partial_failure?
    status == "partial_failure"
  end

  def running?
    status == "running"
  end

  def queued?
    status == "queued"
  end

  private

  def validate_requested_by_is_sway_admin
    return if requested_by.blank?
    return if requested_by.respond_to?(:is_sway_admin?) && requested_by.is_sway_admin?

    errors.add(:requested_by, "must be a Sway admin")
  end
end
