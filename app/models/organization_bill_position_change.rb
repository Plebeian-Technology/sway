# == Schema Information
#
# Table name: organization_bill_position_changes
# Database name: primary
#
#  id                            :integer          not null, primary key
#  new_summary                   :text             not null
#  new_support                   :string           not null
#  previous_summary              :text             not null
#  previous_support              :string           not null
#  rejected_at                   :datetime
#  status                        :integer          not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  approved_by_id                :integer
#  organization_bill_position_id :integer          not null
#  rejected_by_id                :integer
#  updated_by_id                 :integer          not null
#
# Indexes
#
#  idx_on_organization_bill_position_id_789f74d3d4             (organization_bill_position_id)
#  index_organization_bill_position_changes_on_approved_by_id  (approved_by_id)
#  index_organization_bill_position_changes_on_rejected_by_id  (rejected_by_id)
#  index_organization_bill_position_changes_on_updated_by_id   (updated_by_id)
#
# Foreign Keys
#
#  approved_by_id                 (approved_by_id => users.id)
#  organization_bill_position_id  (organization_bill_position_id => organization_bill_positions.id)
#  rejected_by_id                 (rejected_by_id => users.id)
#  updated_by_id                  (updated_by_id => users.id)
#
class OrganizationBillPositionChange < ApplicationRecord
  belongs_to :updated_by, class_name: "User", inverse_of: :authored_position_changes
  belongs_to :approved_by, class_name: "User", optional: true, inverse_of: :approved_position_changes
  belongs_to :rejected_by, class_name: "User", optional: true, inverse_of: :rejected_position_changes

  belongs_to :organization_bill_position

  enum :status, {pending: 0, approved: 1, rejected: 2}, default: :pending

  before_validation :normalize_support_values

  # @lat: [[organization-bill-position-change-design#Why the pending scope filters on two columns together]]
  scope :pending,
    ->(organization) do
      includes(organization_bill_position: :organization).where(
        status: :pending,
        approved_by_id: nil,
        organization_bill_position: {
          organization: organization
        }
      )
    end

  validates :new_summary, presence: {message: "can't be blank"}

  # @lat: [[organization-bill-position-change-design#Why STANCE_TO_SUPPORT lives on OrganizationBillPosition]]
  validates :new_support,
    presence: {message: "can't be blank"},
    inclusion: {in: OrganizationBillPosition::STANCE_TO_SUPPORT.keys, message: "must be a recognized stance"}

  # @lat: [[organization-bill-position-change-design#Why status and its *_by_id columns are validated in both directions]]
  validates :approved_by_id, presence: true, if: -> { status == "approved" }
  validates :rejected_by_id, presence: true, if: -> { status == "rejected" }
  validates :rejected_at, presence: true, if: -> { status == "rejected" }

  validates :approved_by_id, absence: true, if: -> { status != "approved" }
  validates :rejected_by_id, absence: true, if: -> { status != "rejected" }
  validates :rejected_at, absence: true, if: -> { status != "rejected" }

  # @lat: [[organization-bill-position-change-design#Why there is no hand-written approved? override]]
  def finalized?
    approved? || rejected?
  end

  # @lat: [[organization-bill-position-change-design#Why rejection fields serialize even though they're always null today]]
  def to_builder
    Jbuilder.new do |change|
      change.id id
      change.created_at created_at
      change.organization_bill_position_id organization_bill_position_id
      change.approved_by_id approved_by_id
      change.rejected_by_id rejected_by_id
      change.rejected_at rejected_at
      change.status status
      change.updated_by_id updated_by_id
      change.new_summary new_summary
      change.new_support new_support
      change.previous_summary previous_summary
      change.previous_support previous_support
    end
  end

  private

  def normalize_support_values
    if new_support.present?
      normalized_new = OrganizationBillPosition.normalize_support(new_support)
      self.new_support = normalized_new if normalized_new
    end

    if previous_support.present?
      normalized_prev = OrganizationBillPosition.normalize_support(previous_support)
      self.previous_support = normalized_prev if normalized_prev
    end
  end
end
