# frozen_string_literal: true

# == Schema Information
#
# Table name: addresses
# Database name: primary
#
#  id          :integer          not null, primary key
#  city        :string           not null
#  country     :string           default("US"), not null
#  latitude    :float
#  longitude   :float
#  postal_code :string           not null
#  region_code :string           not null
#  street      :string           not null
#  street2     :string
#  street3     :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_addresses_on_latitude_and_longitude  (latitude,longitude)
#
class Address < ApplicationRecord
  after_initialize :find_region_code_from_region_name,
                   :upcase_region_code,
                   :titleize_city_name

  after_validation :geocode, if: ->(_address) { Rails.env.test? }
  after_commit :geocode,
               unless:
                 lambda { |address|
                   Rails.env.test? ||
                     (address&.latitude.present? && address&.longitude.present?)
                 }

  attribute :full_address

  has_one :user_address, dependent: :destroy

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
      longitude: results.coordinates.last,
    )
  end

  def full_address
    [street, city, region_code, postal_code, country].compact.join(", ")
  end

  def sway_locales
    [
      SwayLocale.find_or_create_by_normalized!(
        city:,
        state: region_code,
        country:,
      ),
      SwayLocale.find_or_create_by_normalized!(
        city: RegionUtil.from_region_code_to_region_name(region_code),
        state: region_code,
        country:,
      ),
      SwayLocale.find_or_create_by_normalized!(
        city: "congress",
        state: "congress",
        country:,
      ),
    ]
  end

  # https://rgeo.info/
  def to_cartesian
    RGeo::Cartesian.factory.point(longitude, latitude)
  end

  private

  def geocode
    return unless latitude.nil? || longitude.nil?

    results = Geocoder.search(full_address)
    self.latitude, self.longitude = results.first&.coordinates || []
  end

  def find_region_code_from_region_name
    return unless region_code.length > 2

    self.region_code =
      RegionUtil.from_region_name_to_region_code(region_code) || region_code
  end

  def upcase_region_code
    self.region_code = region_code.upcase
  end

  def titleize_city_name
    self.city = city.titleize
  end
end
