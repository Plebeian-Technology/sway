# frozen_string_literal: true

# == Schema Information
#
# Table name: organization_bill_positions
# Database name: primary
#
#  id              :integer          not null, primary key
#  active          :boolean          default(FALSE), not null
#  summary         :text             not null
#  support         :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  bill_id         :integer          not null
#  organization_id :integer          not null
#
# Indexes
#
#  idx_on_bill_id_organization_id_f380340a40             (bill_id,organization_id) UNIQUE
#  index_organization_bill_positions_on_active           (active)
#  index_organization_bill_positions_on_bill_id          (bill_id)
#  index_organization_bill_positions_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  bill_id          (bill_id => bills.id)
#  organization_id  (organization_id => organizations.id)
#
class OrganizationBillPosition < ApplicationRecord
  DEFAULT_SUMMARY = "Work In Progress."

  belongs_to :bill
  belongs_to :organization

  has_one :sway_locale, through: :organization
  has_many :position_changes,
           class_name: "OrganizationBillPositionChange",
           dependent: :destroy

  validates :bill_id, uniqueness: { scope: :organization_id, allow_nil: true }

  validates :support,
            :summary,
            :organization,
            :bill,
            presence: {
              message: "can't be blank",
            }

  def latest_position_change
    position_changes.order(created_at: :desc).first
  end

  def bill
    super
  end

  def organization
    super
  end

  def to_builder
    Jbuilder.new do |obp|
      obp.id id
      obp.bill_id bill_id
      obp.organization organization.to_simple_builder.attributes!
      obp.support support
      obp.summary summary
    end
  end
end
