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
  has_many :legislators, through: :districts

  # use inverse_of to specify relationship
  # https://stackoverflow.com/a/59222913/6410635
  has_many :districts, inverse_of: :sway_locale

  sig { returns(T::Array[District]) }
  attr_reader :districts

  sig { returns(T::Array[Legislator]) }
  attr_reader :legislators

  sig { params(address: T.nilable(Address)).returns(T.nilable(SwayLocale)) }
  def self.find_or_create_by_address(address)
    address&.sway_locale
  end

  sig { returns(String) }
  def name
    "#{city_name}-#{region_name}-#{country_name}"
  end

  sig { returns(RGeo::GeoJSON::FeatureCollection) }
  def load_geojson
    T.let(RGeo::GeoJSON.decode(File.read("storage/#{name}.geojson")), RGeo::GeoJSON::FeatureCollection)
  end

  private

  sig { returns(String) }
  def country_name
    format_name(T.cast(RegionUtil.from_country_code_to_name(country), String))
  end

  sig { returns(String) }
  def region_name
    format_name(T.cast(RegionUtil.from_region_code_to_region_name(state), String))
  end

  sig { returns(String) }
  def city_name
    format_name(T.cast(city, String))
  end

  sig { params(name: String).returns(String) }
  def format_name(name)
    name.chomp.downcase.split(' ').join('_')
  end
end
