# frozen_string_literal: true

# == Schema Information
#
# Table name: organization_bill_positions
# Database name: primary
#
#  id              :integer          not null, primary key
#  activated_at    :datetime
#  active          :boolean          default(FALSE), not null
#  ai_summary      :text
#  origin_type     :string
#  source_kind     :string
#  source_url      :string
#  summary         :text             not null
#  support         :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  bill_id         :integer          not null
#  organization_id :integer          not null
#  origin_id       :integer
#
# Indexes
#
#  idx_on_bill_id_organization_id_f380340a40             (bill_id,organization_id) UNIQUE
#  index_organization_bill_positions_on_active           (active)
#  index_organization_bill_positions_on_bill_id          (bill_id)
#  index_organization_bill_positions_on_organization_id  (organization_id)
#  index_organization_bill_positions_on_origin           (origin_type,origin_id)
#
# Foreign Keys
#
#  bill_id          (bill_id => bills.id)
#  organization_id  (organization_id => organizations.id)
#
class OrganizationBillPosition < ApplicationRecord
  DEFAULT_SUMMARY = "Work In Progress."

  # @lat: [[organization-bill-position-notification-callbacks#notify_followers_on_change: the guard and the change-label rule]]
  NOTIFIABLE_FIELDS = %i[active support summary].freeze

  # @lat: [[organization-bill-position-change-design#Why STANCE_TO_SUPPORT lives on OrganizationBillPosition]]
  STANCE_TO_SUPPORT = {
    "support" => "FOR",
    "oppose" => "AGAINST",
    "neutral" => "ABSTAIN",
    "FOR" => "FOR",
    "AGAINST" => "AGAINST",
    "ABSTAIN" => "ABSTAIN"
  }.freeze

  NEUTRAL_SUPPORT = STANCE_TO_SUPPORT.fetch("neutral")

  # @lat: [[news-org-position-persistence#Position origin and affiliation]]
  module SourceKind
    HEARING_TESTIMONY = "hearing_testimony"
    NEWS_ARTICLE = "news_article"
    SWAY_ADMIN = "sway_admin"
    ORGANIZATION = "organization"
    ALL = [HEARING_TESTIMONY, NEWS_ARTICLE, SWAY_ADMIN, ORGANIZATION].freeze
  end

  def self.normalize_support(value)
    STANCE_TO_SUPPORT[value.to_s]
  end

  # @lat: [[organization-position-removal#A Neutral position carries no testimony]]
  def self.neutral_support?(value)
    normalize_support(value) == NEUTRAL_SUPPORT
  end

  def neutral?
    self.class.neutral_support?(support)
  end

  # @lat: [[organization-position-removal#Nothing reads a Neutral position's stored placeholder]]
  def summary_for_readers
    neutral? ? nil : summary
  end

  before_validation :normalize_support_value
  before_save :record_activated_at, if: :activating?

  # @lat: [[organization-bill-position-notification-callbacks#notify_followers_on_change: the guard and the change-label rule]]
  after_commit :notify_followers_on_change,
    if: -> { active && NOTIFIABLE_FIELDS.any? { |f| saved_change_to_attribute?(f) } }

  belongs_to :bill
  belongs_to :organization

  has_one :sway_locale, through: :organization
  has_many :position_changes,
    class_name: "OrganizationBillPositionChange",
    dependent: :destroy

  validates :bill_id, uniqueness: {scope: :organization_id, allow_nil: true}
  validates :source_kind, inclusion: {in: SourceKind::ALL}, allow_nil: true

  validates :support,
    :summary,
    :organization,
    :bill,
    presence: {
      message: "can't be blank"
    }

  # @lat: [[organization-bill-position-notification-callbacks#enqueue_interesting_score_recompute: soft-deletes and a tolerated double-enqueue]]
  after_commit :enqueue_interesting_score_recompute

  after_commit :broadcast_feed_update, on: %i[create update]

  def latest_position_change
    position_changes.order(created_at: :desc).first
  end

  # @lat: [[organization-bill-position-ai-summary-flag#Why OrganizationBillPositionResource mirrors PUBLIC_FIELDS]]
  def summary_ai_unreviewed?
    return false if ai_summary.blank?

    summary.to_s == ai_summary.to_s
  end

  def to_builder
    Jbuilder.new do |obp|
      obp.id id
      obp.bill_id bill_id
      obp.organization organization.to_simple_builder.attributes!
      obp.support support
      obp.summary summary_for_readers
      # @lat: [[organization-bill-position-ai-summary-flag#Why OrganizationBillPositionResource mirrors PUBLIC_FIELDS]]
      obp.summary_ai_unreviewed summary_ai_unreviewed?
    end
  end

  # @lat: [[organization-bill-position-ai-summary-flag#Why OrganizationBillPositionResource mirrors PUBLIC_FIELDS]]
  PUBLIC_FIELDS = %i[id organization_id bill_id support summary active created_at].freeze

  def to_public_json
    initial = {} #: Hash[Symbol, untyped]
    PUBLIC_FIELDS.each_with_object(initial) do |field, hash|
      hash[field] = public_send(field) if respond_to?(field)
    end
      # @lat: [[organization-bill-position-ai-summary-flag#Why OrganizationBillPositionResource mirrors PUBLIC_FIELDS]]
      .merge(summary: summary_for_readers, summary_ai_unreviewed: summary_ai_unreviewed?)
  end

  private

  def normalize_support_value
    return if support.blank?

    normalized = self.class.normalize_support(support)
    self.support = normalized if normalized
  end

  def activating?
    will_save_change_to_active?(from: false, to: true)
  end

  def record_activated_at
    return if will_save_change_to_activated_at?

    self.activated_at = Time.current.in_time_zone
  end

  def enqueue_interesting_score_recompute
    RecomputeBillInterestingScoreJob.perform_later(bill_id)
  end

  # @lat: [[organization-bill-position-notification-callbacks#notify_followers_on_change: the guard and the change-label rule]]
  def notify_followers_on_change
    change_types = []
    if saved_change_to_active? && active
      change_types << :new_position
    else
      change_types << :support_change if saved_change_to_support?
      change_types << :summary_change if saved_change_to_summary?
    end
    return if change_types.empty?

    NotifyOrganizationFollowersService.new(self, change_types: change_types).call_later
  rescue Exception => e # rubocop:disable Lint/RescueException
    SwayLogging.log_exception(
      "organization_bill_position.notify_followers_failed",
      exception: e,
      level: :warn,
      organization_bill_position_id: id
    )
    Sentry.capture_exception(e) if Rails.env.production?
  end

  def broadcast_feed_update
    return unless active? && saved_change_to_activated_at?

    user_ids = OrganizationFollow.where(organization_id: organization_id).distinct.pluck(:user_id)
    return if user_ids.empty?

    FeedUpdateBroadcastJob.perform_later(user_ids)
  end
end
