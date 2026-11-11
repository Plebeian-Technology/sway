# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_summary_reports
# Database name: primary
#
#  id                    :integer          not null, primary key
#  admin_notes           :text
#  details               :text
#  ip_address            :string
#  reason                :string           not null
#  resolved_at           :datetime
#  status                :integer          default("pending"), not null
#  summary_ai_unreviewed :boolean          default(TRUE), not null
#  summary_snapshot      :text
#  user_agent            :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  bill_id               :integer          not null
#  resolved_by_id        :integer
#  user_id               :integer
#
# Indexes
#
#  index_bill_summary_reports_on_bill_id                    (bill_id)
#  index_bill_summary_reports_on_bill_id_and_created_at     (bill_id,created_at)
#  index_bill_summary_reports_on_bill_id_and_status         (bill_id,status)
#  index_bill_summary_reports_on_ip_address_and_created_at  (ip_address,created_at)
#  index_bill_summary_reports_on_resolved_by_id             (resolved_by_id)
#  index_bill_summary_reports_on_status                     (status)
#  index_bill_summary_reports_on_user_id                    (user_id)
#
# Foreign Keys
#
#  bill_id         (bill_id => bills.id) ON DELETE => cascade
#  resolved_by_id  (resolved_by_id => users.id) ON DELETE => nullify
#  user_id         (user_id => users.id) ON DELETE => nullify
#
class BillSummaryReport < ApplicationRecord
  VALID_REASONS = %w[
    factual_inaccuracy
    misleading_tone
    missing_amendment
    other
  ].freeze

  REASON_LABELS = {
    "factual_inaccuracy" => "Factual Inaccuracy",
    "misleading_tone" => "Misleading Tone or Bias",
    "missing_amendment" => "Missing Amendment / Outdated",
    "other" => "Other"
  }.freeze

  MAX_DETAILS_LENGTH = 2000
  DUPLICATE_WINDOW_HOURS = 24

  encrypts :ip_address, deterministic: true

  belongs_to :bill, inverse_of: :bill_summary_reports
  belongs_to :user, optional: true, inverse_of: :bill_summary_reports
  belongs_to :resolved_by, class_name: "User", optional: true, inverse_of: :resolved_bill_summary_reports

  enum :status, {pending: 0, reviewed: 1, resolved: 2, dismissed: 3}, default: :pending

  validates :reason, presence: true, inclusion: {in: VALID_REASONS}
  validates :details, length: {maximum: MAX_DETAILS_LENGTH}, allow_blank: true
  validate :throttle_duplicate_reports, on: :create

  before_validation :capture_bill_snapshot, on: :create

  scope :unresolved, -> { where(status: %i[pending reviewed]) }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :for_bill, ->(bill_id) { where(bill_id:) }

  def anonymous?
    user_id.nil?
  end

  def reporter_display_name
    if (u = user)
      u.full_name.presence || u.email.presence || "Registered User ##{user_id}"
    else
      "Anonymous Reader"
    end
  end

  def reason_label
    REASON_LABELS[reason] || reason.to_s.humanize
  end

  private

  def capture_bill_snapshot
    return if bill.blank?

    self.summary_snapshot ||= bill.summary
    self.summary_ai_unreviewed = bill.summary_ai_unreviewed? if summary_ai_unreviewed.nil?
  end

  def throttle_duplicate_reports
    return if bill_id.blank?

    existing_scope = if user_id.present?
      BillSummaryReport.where(bill_id:, user_id:)
    elsif ip_address.present?
      BillSummaryReport.where(bill_id:, ip_address:)
    end

    return unless existing_scope

    recent_pending = existing_scope
      .where("created_at > ?", DUPLICATE_WINDOW_HOURS.hours.ago)
      .where(status: %i[pending reviewed])
      .exists?

    if recent_pending
      errors.add(:base, "A report for this bill summary was already submitted recently. Thank you for your feedback.")
    end
  end
end
