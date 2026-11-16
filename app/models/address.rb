# frozen_string_literal: true

# == Schema Information
#
# Table name: addresses
# Database name: primary
#
#  id                      :integer          not null, primary key
#  city                    :string           not null
#  country                 :string           default("US"), not null
#  geocode_abandoned_at    :datetime
#  geocode_next_attempt_at :datetime
#  latitude                :string
#  longitude               :string
#  normalized_key          :string
#  place_types             :json             not null
#  postal_code             :string           not null
#  region_code             :string           not null
#  street                  :string           not null
#  street2                 :string
#  street3                 :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
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

  GEOCODE_HOURLY_WINDOW = 1.day
  GEOCODE_RETRY_WINDOW = 30.days
  GEOCODE_JITTER_FRACTION = 0.25

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

  def geocode_due?(now = Time.current)
    return false if geocode_abandoned_at.present?

    next_attempt_at = geocode_next_attempt_at
    next_attempt_at.nil? || next_attempt_at <= now
  end

  def geocode_window_over?(now = Time.current)
    now >= created_at + GEOCODE_RETRY_WINDOW
  end

  # @lat: [[registration-dead-ends#A skipped lookup is recorded so it can be retried#An unlocated address waits for its geocode#A failing geocode is retried less often, then dropped]]
  def record_failed_geocode_attempt!(now = Time.current)
    interval = (now < created_at + GEOCODE_HOURLY_WINDOW) ? 1.hour : 1.day
    jitter = Random.rand(-GEOCODE_JITTER_FRACTION..GEOCODE_JITTER_FRACTION)
    next_attempt = [now + (interval * (1 + jitter)), created_at + GEOCODE_RETRY_WINDOW].min
    update_columns(geocode_next_attempt_at: next_attempt)
  end

  def record_geocode_abandoned!(now = Time.current)
    update_columns(geocode_abandoned_at: now)
  end

  def sway_locale_attribute_sets
    self.class.sway_locale_attribute_sets_for(city:, region_code:, country:)
  end

  def to_cartesian
    RGeo::Cartesian.factory.point(longitude.to_f, latitude.to_f)
  end

  def geocode_and_save
    return if located?

    result = Geocoder.search(full_address).first
    latitude, longitude = result&.coordinates
    return if result.nil? || latitude.nil? || longitude.nil?
    return unless trusted_geocode?(result)

    update!(latitude:, longitude:, **blank_fields_from_geocode(result))
    @sway_locales = nil
  rescue => e
    SwayLogging.log_exception("address.geocode_failed", exception: e, address_id: id)
    Sentry.capture_exception(e, extra: {address_id: id})
  end

  private

  def geocode
    return unless latitude.nil? || longitude.nil?

    results = Geocoder.search(full_address)
    self.latitude, self.longitude = results.first&.coordinates || []
  end

  # @lat: [[address-normalized-key#A typed address gets its place from the geocode]]
  def trusted_geocode?(result)
    reason = if result.partial_match == true
      "partial_match"
    elsif !Array(result.types).intersect?(%w[street_address premise subpremise])
      "not_street_level"
    else
      text = full_address
      zip = result.postal_code.to_s[/\A\d{5}/]
      anchored_by_zip = zip.present? && /\b#{Regexp.escape(zip)}\b/i.match?(text)
      city_name = result.city.to_s.strip
      states = [result.state_code, result.state].filter_map { |s| s.to_s.strip.presence }
      anchored_by_city_and_state =
        city_name.present? && /\b#{Regexp.escape(city_name)}\b/i.match?(text) &&
        states.any? { |s| /\b#{Regexp.escape(s)}\b/i.match?(text) }
      "unanchored" unless anchored_by_zip || anchored_by_city_and_state
    end
    return true if reason.nil?

    SwayLogging.warn("address.geocode_untrusted", address_id: id, reason:)
    false
  end

  # @lat: [[address-normalized-key#A typed address gets its place from the geocode]]
  def blank_fields_from_geocode(result)
    found = {
      city: result.city,
      region_code: result.state_code.presence || result.state,
      postal_code: result.postal_code,
      country: result.country_code.to_s.upcase.presence
    }
    found.select { |field, value| public_send(field).blank? && value.present? }
  end

  def normalize_address
    NormalizeAddressService.call(self)
  end
end
