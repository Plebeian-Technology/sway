# frozen_string_literal: true

# == Schema Information
#
# Table name: addresses
# Database name: primary
#
#  id             :integer          not null, primary key
#  city           :string           not null
#  country        :string           default("US"), not null
#  latitude       :string
#  longitude      :string
#  normalized_key :string
#  place_types    :json             not null
#  postal_code    :string           not null
#  region_code    :string           not null
#  street         :string           not null
#  street2        :string
#  street3        :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_addresses_on_normalized_key  (normalized_key)
#
class Address < ApplicationRecord
  # @lat: [[address-normalization]]
  before_validation :normalize_address

  after_validation :geocode, if: ->(_address) { Rails.env.test? }
  # @lat: [[address-normalized-key#Why an unlocated address has no key]]
  after_commit :geocode_and_save, unless: ->(_address) { Rails.env.test? }

  # @lat: [[personal-detail-encryption#What is encrypted on an address]]
  encrypts :street
  encrypts :street2
  encrypts :street3
  # @lat: [[personal-detail-encryption#What is encrypted on an address]]
  encrypts :latitude
  encrypts :longitude

  attribute :full_address

  has_one :user_address, dependent: :destroy

  # @lat: [[address-normalized-key]]
  COORDINATE_KEY_PRECISION = 4

  UNIT_PREFIX = /\A(?:apartment|apt|building|bldg|floor|fl|number|no|room|rm|suite|ste|unit)\b/

  # @lat: [[address-normalized-key#Why an unlocated address has no key]]
  def self.normalized_key_for(latitude:, longitude:, street2: nil, street3: nil)
    return nil if latitude.blank? || longitude.blank?

    [
      latitude.to_f.round(COORDINATE_KEY_PRECISION),
      longitude.to_f.round(COORDINATE_KEY_PRECISION),
      normalized_unit_part(street2),
      normalized_unit_part(street3)
    ].join("|")
  end

  def self.normalized_unit_part(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip.sub(UNIT_PREFIX, "").delete(" ")
  end

  def computed_normalized_key
    self.class.normalized_key_for(latitude:, longitude:, street2:, street3:)
  end

  def full_address
    [street, city, region_code, postal_code, country].compact.join(", ")
  end

  # @lat: [[inertia-user-prop-address-whitelist#Why TParsedGoogleAddress carries latitude/longitude but sway.IAddress does not]]
  def to_builder
    Jbuilder.new do |b|
      b.id id
      b.street street
      b.street2 street2
      b.city city
      b.region_code region_code
      b.country country
      b.postal_code postal_code
      b.full_address full_address
    end
  end

  def sway_locales
    @sway_locales ||= sway_locale_attribute_sets.map do |attrs|
      SwayLocale.find_or_create_by_normalized!(**attrs)
    end
  end

  # @lat: [[locale-user-counts#Why the attribute sets are reachable without a record]]
  def self.sway_locale_attribute_sets_for(city:, region_code:, country:)
    country = country.presence || "US"
    sets = [] #: Array[Hash[Symbol, String?]]
    if region_code.present?
      sets << {city:, state: region_code, country:} if city.present?
      sets << {city: RegionUtil.from_region_code_to_region_name(region_code), state: region_code, country:}
    end
    sets << {city: "congress", state: "congress", country: "US"}
  end

  # @lat: [[representative-resolution#Congress fallback]]
  def us_state_code
    code = RegionUtil.from_region_name_to_region_code(region_code)
    return nil if code.nil? || code == "US" || !RegionUtil::STATE_CODES_NAMES.key?(code.to_sym)
    return nil unless country.blank? || RegionUtil.from_country_code_to_name(country) == "United States"

    code
  end

  def located?
    latitude.present? && longitude.present?
  end

  def sway_locale_attribute_sets
    self.class.sway_locale_attribute_sets_for(city:, region_code:, country:)
  end

  def to_cartesian
    RGeo::Cartesian.factory.point(longitude.to_f, latitude.to_f)
  end

  private

  def geocode
    return unless latitude.nil? || longitude.nil?

    results = Geocoder.search(full_address)
    self.latitude, self.longitude = results.first&.coordinates || []
  end

  def geocode_and_save
    return if located?

    latitude, longitude = Geocoder.search(full_address).first&.coordinates
    return if latitude.nil? || longitude.nil?

    update!(latitude:, longitude:, normalized_key: self.class.normalized_key_for(latitude:, longitude:, street2:, street3:))
  rescue Geocoder::Error, Timeout::Error, SocketError => e
    SwayLogging.log_exception("address.geocode_failed", exception: e, address_id: id)
    Sentry.capture_exception(e, extra: {address_id: id})
  end

  def normalize_address
    NormalizeAddressService.call(self)
  end
end
