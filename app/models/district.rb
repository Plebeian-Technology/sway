# typed: true

# == Schema Information
#
# Table name: districts
#
#  id             :integer          not null, primary key
#  name           :string
#  sway_locale_id :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class District < ApplicationRecord
  extend T::Sig

  # use inverse_of to specify relationship
  # https://stackoverflow.com/a/59222913/6410635
  belongs_to :sway_locale, inverse_of: :districts

  has_many :legislators, inverse_of: :district

  sig { returns(T.nilable(Integer)) }
  def number
    name&.remove_non_digits&.to_i
  end
end
