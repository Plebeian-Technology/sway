# typed: true

# == Schema Information
#
# Table name: sway_locales
#
#  id         :integer          not null, primary key
#  city       :string           not null
#  state      :string           not null
#  country    :string           default("United States"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class SwayLocale < ApplicationRecord
  extend T::Sig

  has_many :bills
  has_many :districts
  has_many :legislators, through: :districts

  sig { params(address: T.nilable(Address)).returns(T.nilable(SwayLocale)) }
  def self.find_or_create_by_address(address)
    address&.sway_locale
  end
end
