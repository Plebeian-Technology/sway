# typed: true

# == Schema Information
#
# Table name: organizations
#
#  id             :integer          not null, primary key
#  sway_locale_id :integer          not null
#  name           :string           not null
#  icon_path      :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class Organization < ApplicationRecord
  extend T::Sig

  belongs_to :sway_locale

  has_many :organization_bill_positions, inverse_of: :organization
  has_many :bills, through: :organization_bill_positions

  validates_uniqueness_of :name, scope: :sway_locale_id, allow_nil: true

  sig { params(with_positions: T::Boolean).returns(Jbuilder) }
  def to_builder with_positions:
    Jbuilder.new do |o|
      o.id id
      o.sway_locale_id sway_locale_id
      o.name name
      o.icon_path icon_path

      if with_positions
        o.positions organization_bill_positions.map{ |obp| obp.to_builder.attributes! }
      end
    end

  end
end
