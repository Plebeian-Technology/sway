# typed: true

# frozen_string_literal: true

# Creates Legislators in Sway only if they do not exist
class SeedLegislator
  extend T::Sig

  class MissingRegionCode < StandardError; end

  class NonStateRegionCode < StandardError; end

  attr_reader :j
  attr_reader :sway_locale

  sig { params(j: T::Hash[String, String]).void }
  def initialize(j)
    @sway_locale = sway_locale

    if congress?
      api_key = ENV["CONGRESS_API_KEY"]
      if api_key.blank?
        raise "No Congress API Key Found. Cannot seed Legislator."
      end

      bioguide_id = j.fetch("bioguideId", nil)
      if bioguide_id.blank?
        raise "No bioguide id in Legislator json. Cannot seed Legislator."
      end

      @j = JSON.parse(Faraday.get("https://api.congress.gov/v3/member/#{bioguide_id}?&api_key=#{api_key}").body)["member"]
      @j["link"] = "https://api.congress.gov/v3/member/#{bioguide_id}"
    else
      @j = j
    end
  end

  sig { params(sway_locales: T::Array[SwayLocale]).void }
  def self.run(sway_locales)
    sway_locales.each do |sway_locale|
      T.let(read_legislators(sway_locale), T::Array[T::Hash[String, String]]).each do |j|
        SeedLegislator.new(j, sway_locale).seed
      end
    end
  end

  sig { params(sway_locale: SwayLocale).returns(T::Array[T::Hash[String, String]]) }
  def self.read_legislators(sway_locale)
    T.let(JSON.parse(File.read("storage/seeds/data/#{sway_locale.reversed_name.tr("-", "/")}/legislators.json")),
      T::Array[T::Hash[String, String]])
  end

  sig { returns(Legislator) }
  def seed(sway_locale)
    legislator(sway_locale)
  end

  sig { returns(Legislator) }
  def legislator(sway_locale)
    l = Legislator.find_or_initialize_by(
      external_id:,
      first_name:,
      last_name:
    )

    l.address = address
    l.district = district(sway_locale)
    l.title = title
    l.active = active
    l.party = party
    l.photo_url = photo_url
    l.phone = j.fetch("phone", nil)
    l.email = j.fetch("email", nil)
    l.twitter = j.fetch("twitter", nil)
    l.link = j.fetch("link", nil)

    l.save!
    l
  end

  sig { returns(District) }
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
    @_external_id ||= if congress?
      j.fetch("bioguideId", nil)
    else
      j.fetch("externalId", j.fetch("external_id", nil))
    end
  end

  def active
    if congress?
      j.fetch("currentMember")
    else
      j.fetch("active")
    end
  end

  def title
    if congress?
      (j.fetch("terms").last&.chamber == "Senate") ? "Sen." : "Rep."
    else
      j.fetch("title")
    end
  end

  def party
    if congress?
      j.fetch("partyHistory").first&.fetch("partyAbbreviation")
    else
      j.fetch("party", nil)
    end
  end

  def first_name
    @_first_name ||= if congress?
      j.fetch("name").split(", ").last
    else
      j.fetch("firstName", j.fetch("first_name", nil))
    end
  end

  def last_name
    @_last_name ||= if congress?
      j.fetch("name").split(", ").first
    else
      j.fetch("lastName", j.fetch("last_name", nil))
    end
  end

  def country
    @_country ||= RegionUtil.from_country_code_to_name(j.fetch("country", "United States"))
  end

  def region_code
    @_region_code ||= if congress?
      RegionUtil.from_region_name_to_region_code(j.fetch("state"))
    else
      RegionUtil.from_region_name_to_region_code(
        j.fetch("regionCode", j.fetch("region_code", j.fetch("region", "")))
      )
    end
  end

  def postal_code
    @_postal_code ||= j.fetch("postalCode", j.fetch("postal_code", j.fetch("zip", j.fetch("zip_code", j.fetch("zipCode", nil)))))
  end

  def photo_url
    @_photo_url ||= if congress?
      j.dig("depiction", "imageUrl")
    else
      j.fetch("photoURL", j.fetch("photoUrl", j.fetch("photo_url", nil)))
    end
  end

  def congress?
    sway_locale.congress?
  end
end
