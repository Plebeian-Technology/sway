# typed: true

# frozen_string_literal: true

# Creates Legislators in Sway only if they do not exist
class SeedLegislator
  extend T::Sig

  class MissingRegionCode < StandardError; end

  class NonStateRegionCode < StandardError; end

  attr_reader :j
  attr_reader :sway_locale

  sig { params(j: T::Hash[String, String], sway_locale: SwayLocale).void }
  def initialize(j, sway_locale)
    @sway_locale = sway_locale

    if congress?
      api_key = ENV["CONGRESS_GOV_API_KEY"]
      if api_key.blank?
        raise "No Congress API Key Found. Cannot seed Legislator in #{Rails.env}."
      end

      bioguide_id = j.fetch("bioguideId", nil)
      if bioguide_id.blank?
        raise "No bioguide id in Legislator json. Cannot seed Legislator."
      end

      d = (j.fetch("district", nil).presence || "0").to_s
      if Legislator.joins(:district).find_by(
        active: true,
        external_id: bioguide_id,
        district: {
          name: SeedLegislator.district_name(
            RegionUtil.from_region_name_to_region_code(j.fetch("state")),
            d&.remove_non_digits&.to_i
          )
        },
        party: Legislator.to_party_char_from_name(j.fetch("partyName"))
      ).present?
        Rails.logger.info("SKIP Seeding Congressional Legislator #{bioguide_id}. Already exists by external_id, district.name and party char.")
        return
      end

      response = Faraday.get("https://api.congress.gov/v3/member/#{bioguide_id}?&api_key=#{api_key}")
      @j = JSON.parse(response.body)["member"]
      if @j.nil?
        raise "No legislator data from congress.gov member object - #{response.body}."
      end
      @j["link"] = "https://api.congress.gov/v3/member/#{bioguide_id}"
    else
      @j = j
    end
  end

  sig { params(sway_locales: T::Array[SwayLocale]).void }
  def self.run(sway_locales)
    sway_locales.each do |sway_locale|
      T.let(read_legislators(sway_locale), T::Array[T::Hash[String, String]]).each do |j|
        seed_legislator = SeedLegislator.new(j, sway_locale)
        if seed_legislator.present? && seed_legislator.j.present?
          seed_legislator.seed
        end
      end
    end
  end

  sig { params(sway_locale: SwayLocale).returns(T::Array[T::Hash[String, String]]) }
  def self.read_legislators(sway_locale)
    T.let(JSON.parse(File.read("storage/seeds/data/#{sway_locale.reversed_name.tr("-", "/")}/legislators.json")),
      T::Array[T::Hash[String, String]])
  end

  sig { params(region_code: String, district: Integer).returns(String) }
  def self.district_name(region_code, district)
    "#{region_code}#{district}"
  end

  sig { returns(Legislator) }
  def seed
    legislator
  end

  sig { returns(Legislator) }
  def legislator
    Rails.logger.info("Seeding #{sway_locale.city.titleize} Legislator #{external_id}")

    l = Legislator.find_or_initialize_by(
      external_id:,
      first_name:,
      last_name:
    )

    l.address = address
    l.district = district
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
  def district
    if region_code.blank?
      raise MissingRegionCode.new("No regionCode attribute found in legislator json. Sway locale - #{sway_locale.name}, Legislator - #{external_id}")
    end

    # Used in sway_registration_service.district_legislators
    unless RegionUtil::STATE_CODES_NAMES.key?(region_code.to_sym)
      raise NonStateRegionCode.new("regionCode must be a US state (until Sway goes international :) - Received #{region_code}")
    end

    d = (j.fetch("district", nil).presence || "0").to_s
    name = SeedLegislator.district_name(region_code, d&.remove_non_digits&.to_i)

    District.find_or_create_by!(
      name:,
      sway_locale:
    )
  end

  sig { returns(Address) }
  def address
    a = Address.find_or_initialize_by(
      street: congress? ? "US Capitol Building" : j.fetch("street"),
      city: congress? ? "Washington" : j.fetch("city", "").titleize,
      region_code: congress? ? "DC" : region_code,
      postal_code:,
      country: country
    )

    a.street2 = j.fetch("street2", j.fetch("street_2", nil))
    a.latitude = congress? ? 38.89035223641187 : 0.0 if a.latitude.blank?
    a.longitude = congress? ? -77.00911487638015 : 0.0 if a.longitude.blank?

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
      (j.fetch("terms").last&.fetch("chamber", nil) == "Senate") ? "Sen." : "Rep."
    else
      j.fetch("title")
    end
  end

  def party
    @_party ||= if congress?
      Legislator.to_party_char_from_name(j.fetch("partyHistory").first&.fetch("partyAbbreviation"))
    else
      Legislator.to_party_char_from_name(j.fetch("party", nil))
    end
  end

  def first_name
    @_first_name ||= if congress?
      j.fetch("firstName")
    else
      j.fetch("firstName", j.fetch("first_name", nil))
    end
  end

  def last_name
    @_last_name ||= if congress?
      j.fetch("lastName")
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
    @_postal_code ||= if congress?
      j.dig("addressInformation", "zipCode")
    else
      j.fetch("postalCode", j.fetch("postal_code", j.fetch("zip", j.fetch("zip_code", j.fetch("zipCode", nil)))))
    end
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
