# typed: strict
# frozen_string_literal: true

# == Schema Information
#
# Table name: addresses
#
#  id          :integer          not null, primary key
#  street      :string           not null
#  street_2    :string
#  street_3    :string
#  city        :string           not null
#  region_code :string           not null
#  postal_code :string           not null
#  country     :string           default("US"), not null
#  latitude    :float
#  longitude   :float
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Address < ApplicationRecord
  extend T::Sig

  after_initialize :find_region_code_from_region_name, :upcase_region_code, :titleize_city_name

  after_validation :geocode, if: ->(_address) { Rails.env.test? }
  after_create :geocode, unless: lambda { |address|
                                   Rails.env.test? || (address&.latitude.present? && address&.longitude.present?)
                                 }

  sig { params(address_string: T.nilable(String)).returns(T.nilable(Address)) }
  def self.from_string(address_string)
    return nil if address_string.blank?

    results = Geocoder.search(address_string).first
    return nil if results.nil?

    Address.new(
      street: results.street || results.address,
      city: results.city,
      region_code: results.state,
      postal_code: results.postal_code,
      latitude: results.coordinates.first,
      longitude: results.coordinates.last
    )
  end

  sig { returns(String) }
  def full_address
    [street, city, region_code, postal_code, country].compact.join(', ')
  end

  sig { returns(T::Array[SwayLocale]) }
  def sway_locales
    [
      SwayLocale.find_or_create_by_normalized!(
        city:,
        state: region_code,
        country:
      ),
      SwayLocale.find_or_create_by_normalized!(
        city: T.cast(RegionUtil.from_region_code_to_region_name(region_code), String),
        state: region_code,
        country:
      ),
      SwayLocale.find_or_create_by_normalized!(
        city: 'congress',
        state: 'congress',
        country:
      )
    ]
  end

  # https://rgeo.info/
  sig { returns(RGeo::Cartesian::PointImpl) }
  def to_cartesian
    T.let(RGeo::Cartesian.factory.point(longitude, latitude), RGeo::Cartesian::PointImpl)
  end

  private

  sig { void }
  def geocode
    return unless latitude.nil? || longitude.nil?

    results = Geocoder.search(full_address)
    self.latitude, self.longitude = results.first&.coordinates || []
  end

  sig { void }
  def find_region_code_from_region_name
    return unless region_code.length > 2

    self.region_code = RegionUtil.from_region_name_to_region_code(region_code) || region_code
  end

  sig { void }
  def upcase_region_code
    self.region_code = region_code.upcase
  end

  sig { void }
  def titleize_city_name
    self.city = city.titleize
  end
end
