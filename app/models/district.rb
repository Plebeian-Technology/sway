# frozen_string_literal: true

# == Schema Information
#
# Table name: districts
# Database name: primary
#
#  id             :integer          not null, primary key
#  name           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_districts_on_name_and_sway_locale_id  (name,sway_locale_id) UNIQUE
#  index_districts_on_sway_locale_id           (sway_locale_id)
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
class District < ApplicationRecord
  belongs_to :sway_locale, inverse_of: :districts

  # @lat: [[representative-resolution#Seat identity]]
  has_many :legislator_terms,
    inverse_of: :district,
    dependent: :restrict_with_exception
  has_many :seats, inverse_of: :district, dependent: :restrict_with_exception
  has_many :bill_score_districts, inverse_of: :district, dependent: :destroy
  has_many :representative_reassignments, dependent: :nullify

  def number
    name.remove_non_digits.to_i
  end

  # @lat: [[scores-and-agreement#An at-large official has no district tally worth drawing]]
  def at_large?
    number.zero?
  end

  def region_code
    name.remove_non_alpha.upcase
  end

  def to_builder
    Jbuilder.new do |d|
      d.name name
      d.number number
      d.region_code region_code
    end
  end
end
