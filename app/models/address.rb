# typed: strict

# == Schema Information
#
# Table name: addresses
#
#  id                  :bigint           not null, primary key
#  street              :string           not null
#  street_2            :string
#  street_3            :string
#  city                :string           not null
#  state_province_code :string           not null
#  postal_code         :string           not null
#  country             :string           default("US"), not null
#  latitude            :float
#  longitude           :float
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
class Address < ApplicationRecord
  extend T::Sig

  after_initialize :upcase_state_province_code, :titleize_city_name

  after_validation :geocode, if: Rails.env.test?
  after_create :geocode, unless: Rails.env.test?

  sig { returns(Address) }
  def self.from_string
    Address.new
  end

  sig { returns(String) }
  def full_address
    [street, city, state_province_code, postal_code, country].compact.join(', ')
  end

  private

  sig { void }
  def geocode
    results = Geocoder.search(full_address)
    self.latitude, self.longitude = results.first.coordinates
  end

  sig { void }
  def upcase_state_province_code
    self.state_province_code = state_province_code.upcase
  end

  sig { void }
  def titleize_city_name
    self.city = city.titleize
  end
end
