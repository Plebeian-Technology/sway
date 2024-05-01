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

  has_one :legislator, inverse_of: :district

  # attr_reader :sway_locale

  # sig { returns(T::Array[District]) }
  def all_no_locale
    # https://stackoverflow.com/questions/10084355/eager-loading-and-lazy-loading-in-rails
    # District.find(:all, include: [])
    District.all
  end

  sig { returns(T.nilable(Integer)) }
  def number
    name&.remove_non_digits&.to_i
  end
end
