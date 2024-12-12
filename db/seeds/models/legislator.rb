# typed: true

# frozen_string_literal: true

# Creates Legislators in Sway only if they do not exist
class SeedLegislator
  extend T::Sig

  class MissingRegionCode < StandardError; end

  class NonStateRegionCode < StandardError; end

  attr_reader :j

  sig { params(j: T::Hash[String, String]).void }
  def initialize(j)
    @j = j
  end

  sig { params(sway_locales: T::Array[SwayLocale]).void }
  def self.run(sway_locales)
    sway_locales.each do |sway_locale|
      T.let(read_legislators(sway_locale), T::Array[T::Hash[String, String]]).each do |j|
        SeedLegislator.new(j).seed(sway_locale)
      end
    end
  end

  sig { params(sway_locale: SwayLocale).returns(T::Array[T::Hash[String, String]]) }
  def self.read_legislators(sway_locale)
    T.let(JSON.parse(File.read("storage/seeds/data/#{sway_locale.reversed_name.tr("-", "/")}/legislators.json")),
      T::Array[T::Hash[String, String]])
  end

  sig { params(sway_locale: SwayLocale).returns(Legislator) }
  def seed(sway_locale)
    legislator(sway_locale)
  end

  sig { params(sway_locale: SwayLocale).returns(Legislator) }
  def legislator(sway_locale)
    l = Legislator.find_or_initialize_by(
      external_id:,
      first_name:,
      last_name:
    )

    l.address = address
    l.district = district(sway_locale)
    l.title = j.fetch("title")
    l.active = j.fetch("active")
    l.party = j.fetch("party")
    l.phone = j.fetch("phone")
    l.email = j.fetch("email")
    l.twitter = j.fetch("twitter")
    l.photo_url = photo_url
    l.link = j.fetch("link")

    l.save!
    l
  end

  sig { params(sway_locale: SwayLocale).returns(District) }
  def district(sway_locale)
    if region_code.blank?
      raise MissingRegionCode.new("No regionCode attribute found in legislator json. Sway locale - #{sway_locale.name}, Legislator - #{external_id}")
    end

    # Used in sway_registration_service.district_legislators
    unless RegionUtil::STATE_CODES_NAMES.key?(region_code.to_sym)
      raise NonStateRegionCode.new("regionCode must be a US state (until Sway goes international :) - Received #{region_code}")
    end

    d = j.fetch("district").presence || "0"
    name = d.is_numeric? ? "#{region_code}#{d}" : d

    District.find_or_create_by!(
      name:,
      sway_locale:
    )
  end

  sig { returns(Address) }
  def address
    a = Address.find_or_initialize_by(
      street: j.fetch("street"),
      city: j.fetch("city", "").titleize,
      region_code:,
      postal_code:,
      country: country
    )

    a.street2 = j.fetch("street2", j.fetch("street_2", nil))
    a.latitude = 0.0 if a.latitude.blank?
    a.longitude = 0.0 if a.longitude.blank?

    a.save!
    a
  end

  private

  def external_id
    @_external_id ||= j.fetch("externalId", j.fetch("external_id", nil))
  end

  def first_name
    @_first_name ||= j.fetch("firstName", j.fetch("first_name", nil))
  end

  def last_name
    @_last_name ||= j.fetch("lastName", j.fetch("last_name", nil))
  end

  def country
    @_country ||= RegionUtil.from_country_code_to_name(j.fetch("country", "United States"))
  end

  def region_code
    @_region_code ||= RegionUtil.from_region_name_to_region_code(
      j.fetch("regionCode", j.fetch("region_code", j.fetch("region", "")))
    )
  end

  def postal_code
    @_postal_code ||= j.fetch("postalCode", j.fetch("postal_code", j.fetch("zip", j.fetch("zip_code", j.fetch("zipCode", nil)))))
  end

  def photo_url
    @_photo_url ||= j.fetch("photoURL", j.fetch("photoUrl", j.fetch("photo_url", nil)))
  end
end
