# typed: true

# == Schema Information
#
# Table name: organization_bill_positions
#
#  id              :integer          not null, primary key
#  bill_id         :integer          not null
#  organization_id :integer          not null
#  support         :string           not null
#  summary         :text             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
class OrganizationBillPosition < ApplicationRecord
  extend T::Sig

  belongs_to :bill
  belongs_to :organization

  has_one :sway_locale, through: :organization

  validates_uniqueness_of :bill_id, scope: :organization_id

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
