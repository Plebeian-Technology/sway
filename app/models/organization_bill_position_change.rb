# typed: true

# == Schema Information
#
# Table name: organization_bill_position_changes
#
#  id                            :integer          not null, primary key
#  new_summary                   :text             not null
#  new_support                   :string           not null
#  previous_summary              :text             not null
#  previous_support              :string           not null
#  status                        :integer          not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  approved_by_id                :integer
#  organization_bill_position_id :integer          not null
#  updated_by_id                 :integer          not null
#
# Indexes
#
#  idx_on_organization_bill_position_id_789f74d3d4             (organization_bill_position_id)
#  index_organization_bill_position_changes_on_approved_by_id  (approved_by_id)
#  index_organization_bill_position_changes_on_updated_by_id   (updated_by_id)
#
# Foreign Keys
#
#  approved_by_id                 (approved_by_id => users.id)
#  organization_bill_position_id  (organization_bill_position_id => organization_bill_positions.id)
#  updated_by_id                  (updated_by_id => users.id)
#
class OrganizationBillPositionChange < ApplicationRecord
  extend T::Sig

  belongs_to :updated_by, class_name: "User"
  belongs_to :approved_by, class_name: "User", optional: true

  belongs_to :organization_bill_position

  enum :status, { pending: 0, approved: 1, rejected: 2 }, default: :pending

  # before save, if was pending and approver is not nil, set to approved

  sig { returns(T.nilable(User)) }
  def approver
    T.unsafe(self).approved_by
  end

  sig { returns(User) }
  def updater
    T.unsafe(self).updated_by
  end

  sig { returns(T.nilable(OrganizationBillPosition)) }
  def position
    T.unsafe(self).organization_bill_position
  end

  def approved?
    !approved_by_id.nil?
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |change|
      change.id id
      change.created_at created_at
      change.organization_bill_position_id organization_bill_position_id
      change.approved_by_id approved_by_id
      change.updated_by_id updated_by_id
      change.new_summary new_summary
      change.new_support new_support
      change.previous_summary previous_summary
      change.previous_support previous_support
    end
  end
end
