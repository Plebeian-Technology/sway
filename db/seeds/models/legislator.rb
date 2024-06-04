# typed: true

# frozen_string_literal: true

# Creates Legislators in Sway only if they do not exist
class SeedLegislator
  extend T::Sig

  sig { params(sway_locales: T::Array[SwayLocale]).void }
  def self.run(sway_locales)
    sway_locales.each do |sway_locale|
      T.let(read_legislators(sway_locale), T::Array[T::Hash[String, String]]).each do |json|
        SeedLegislator.new.seed(T.let(json, T::Hash[String, String]), sway_locale)
      end
    end
  end

  sig { params(sway_locale: SwayLocale).returns(T::Array[T::Hash[String, String]]) }
  def self.read_legislators(sway_locale)
    T.let(JSON.parse(File.read("storage/seeds/data/#{sway_locale.reversed_name.gsub('-', '/')}/legislators.json")),
          T::Array[T::Hash[String, String]])
  end

  sig { params(json: T::Hash[String, String], sway_locale: SwayLocale).returns(Legislator) }
  def seed(json, sway_locale)
    legislator(json, sway_locale)
  end

  sig { params(json: T::Hash[String, T.untyped], sway_locale: SwayLocale).returns(Legislator) }
  def legislator(json, sway_locale)
    l = Legislator.find_or_initialize_by(
      external_id: json.fetch('externalId', json.fetch('external_id', nil)),
      first_name: json.fetch('firstName', json.fetch('first_name', nil)),
      last_name: json.fetch('lastName', json.fetch('last_name', nil))
    )

    l.address = address(json)
    l.district = district(json, sway_locale)
    l.title = json.fetch('title')
    l.active = json.fetch('active')
    l.party = json.fetch('party')
    l.phone = json.fetch('phone')
    l.email = json.fetch('email')
    l.twitter = json.fetch('twitter')
    l.photo_url = json.fetch('photoURL', json.fetch('photoUrl', json.fetch('photo_url', nil)))
    l.link = json.fetch('link')

    l.save!
    l
  end

  sig { params(json: T::Hash[String, String], sway_locale: SwayLocale).returns(District) }
  def district(json, sway_locale)
    d = json.fetch('district').present? ? json.fetch('district') : '0'
    name = d.is_numeric? ? "#{json.fetch('regionCode', 'US')}#{d}" : d
    District.find_or_create_by!(
      name:,
      sway_locale:
    )
  end

  sig { params(json: T::Hash[String, String]).returns(Address) }
  def address(json)
    a = Address.find_or_initialize_by(
      street: json.fetch('street'),
      city: json.fetch('city', '').titleize,
      region_code: RegionUtil.from_region_name_to_region_code(
        json.fetch('regionCode', json.fetch('region_code', json.fetch('region', '')))
      ),
      postal_code: json.fetch('postalCode', json.fetch('postal_code', json.fetch('zip', nil))),
      country: RegionUtil.from_country_code_to_name(json.fetch('country', 'United States'))
    )

    a.street2 = json.fetch('street2', json.fetch('street_2', nil))
    a.latitude = 0.0 unless a.latitude.present?
    a.longitude = 0.0 unless a.longitude.present?

    a.save!
    a
  end
end
