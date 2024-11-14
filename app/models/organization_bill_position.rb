# frozen_string_literal: true
# typed: true

# == Schema Information
#
# Table name: organization_bill_positions
#
#  id              :integer          not null, primary key
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
#  index_organization_bill_positions_on_bill_id          (bill_id)
#  index_organization_bill_positions_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  bill_id          (bill_id => bills.id)
#  organization_id  (organization_id => organizations.id)
#
class OrganizationBillPosition < ApplicationRecord
  extend T::Sig

  belongs_to :bill
  belongs_to :organization

  has_one :sway_locale, through: :organization

  validates :bill_id, uniqueness: {scope: :organization_id, allow_nil: true}

  sig { returns(Bill) }
  def bill
    T.cast(super, Bill)
  end

  sig { returns(Organization) }
  def organization
    T.cast(super, Organization)
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |obp|
      obp.id id
      obp.bill_id bill_id
      obp.organization organization.to_builder(with_positions: false).attributes!
      obp.support support
      obp.summary summary
    end
  end
end
