# typed: strict
# frozen_string_literal: true

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

  after_initialize :find_state_code_from_state_name, :upcase_state_province_code, :titleize_city_name

  after_validation :geocode, if: Rails.env.test?
  after_create :geocode, unless: lambda { |address|
                                   Rails.env.test? || (address&.latitude.present? && address&.longitude.present?)
                                 }

  sig { params(address_string: String).returns(T.nilable(Address)) }
  def self.from_string(address_string)
    results = Geocoder.search(address_string).first
    return nil if results.nil?

    Address.new(
      street: results.street || results.address,
      city: results.city,
      state_province_code: results.state,
      postal_code: results.postal_code,
      latitude: results.coordinates.first,
      longitude: results.coordinates.last
    )
  end

  sig { returns(String) }
  def full_address
    [street, city, state_province_code, postal_code, country].compact.join(', ')
  end

  private

  sig { void }
  def geocode
    return unless latitude.nil? || longitude.nil?

    results = Geocoder.search(full_address)
    self.latitude, self.longitude = results.first&.coordinates || []
  end

  sig { void }
  def find_state_code_from_state_name
    return unless state_province_code.length > 2

    self.state_province_code = SwayRails::STATE_NAMES_CODES[state_province_code.titlecase.to_sym]
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
