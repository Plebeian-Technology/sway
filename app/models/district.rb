# frozen_string_literal: true
# typed: true

# == Schema Information
#
# Table name: districts
#
#  id             :integer          not null, primary key
#  name           :string           not null
#  sway_locale_id :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class District < ApplicationRecord
  extend T::Sig

  # use inverse_of to specify relationship
  # https://stackoverflow.com/a/59222913/6410635
  belongs_to :sway_locale, inverse_of: :districts

  has_many :legislators, inverse_of: :district, dependent: :restrict_with_exception
  has_many :bill_score_districts, inverse_of: :district, dependent: :destroy

  sig { returns(SwayLocale) }
  def sway_locale
    T.cast(super, SwayLocale)
  end

  sig { returns(Integer) }
  def number
    name.remove_non_digits.to_i
  end

  sig { returns(String) }
  def region_code
    name.remove_non_alpha.upcase
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |d|
      d.name name
      d.number number
      d.region_code region_code
    end
  end
end
