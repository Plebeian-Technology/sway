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

  sig { params(json: T::Hash[String, String], sway_locale: SwayLocale).returns(Legislator) }
  def legislator(json, sway_locale)
    Legislator.find_or_create_by!(
      address: address(json),
      district: district(json, sway_locale),
      title: json.fetch('title'),
      external_id: json.fetch('externalId', json.fetch('external_id', nil)),
      first_name: json.fetch('firstName', json.fetch('first_name', nil)),
      last_name: json.fetch('lastName', json.fetch('last_name', nil)),
      active: json.fetch('active'),
      party: json.fetch('party'),
      phone: json.fetch('phone'),
      email: json.fetch('email'),
      twitter: json.fetch('twitter'),
      photo_url: json.fetch('photoURL', json.fetch('photoUrl', json.fetch('photo_url', nil))),
      link: json.fetch('link')
    )
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
    Address.find_or_create_by!(
      street: json.fetch('street'),
      street2: json.fetch('street2', json.fetch('street2', nil)),
      city: json.fetch('city', '').titleize,
      region_code: RegionUtil.from_region_name_to_region_code(
        json.fetch('regionCode', json.fetch('region_code', json.fetch('region', '')))
      ),
      postal_code: json.fetch('postalCode', json.fetch('postal_code', json.fetch('zip', nil))),
      country: RegionUtil.from_country_code_to_name(json.fetch('country', 'United States')),
      latitude: 0,
      longitude: 0
    )
  end
end
