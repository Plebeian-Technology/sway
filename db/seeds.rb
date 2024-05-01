# typed: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

module Seeds
  extend T::Sig

  class SeedLegislator
    extend T::Sig

    sig { void }
    def self.run
      T.let(read_legislators, T::Array[T::Hash[String, String]]).each do |json|
        SeedLegislator.new.seed(T.let(json, T::Hash[String, String]))
      end
    end

    def self.read_legislators
      T.let(JSON.parse(File.read('db/seeds/data/united_states/maryland/baltimore/legislators.json')),
            T::Array[T::Hash[String, String]])
    end

    sig { params(j: T::Hash[String, String]).returns(Legislator) }
    def seed(j)
      legislator(j)
    end

    sig { params(j: T::Hash[String, String]).returns(Legislator) }
    def legislator(j)
      d = district(j)

      Legislator.find_or_create_by!(
        address: address(j),
        district: d,
        title: j.fetch('title'),
        external_id: j.fetch('externalId', j.fetch('external_id', nil)),
        first_name: j.fetch('firstName', j.fetch('first_name', nil)),
        last_name: j.fetch('lastName', j.fetch('last_name', nil)),
        active: j.fetch('active'),
        party: j.fetch('party'),
        phone: j.fetch('phone'),
        email: j.fetch('email'),
        twitter: j.fetch('twitter'),
        photo_url: j.fetch('photoURL', j.fetch('photo_url', nil)),
        link: j.fetch('link')
      )
    end

    sig { params(j: T::Hash[String, String]).returns(District) }
    def district(j)
      District.find_or_create_by!(
        name: j.fetch('district'),
        sway_locale: address(j).sway_locale
      )
    end

    sig { params(j: T::Hash[String, String]).returns(Address) }
    def address(j)
      Address.find_or_create_by!(
        street: j.fetch('street'),
        street_2: j.fetch('street2', j.fetch('street_2', nil)),
        city: j.fetch('city', '').titleize,
        region_code: RegionUtil.from_region_name_to_region_code(
          j.fetch('regionCode', j.fetch('region_code', j.fetch('region', '')))
        ),
        postal_code: j.fetch('postalCode', j.fetch('postal_code', j.fetch('zip', nil))),
        country: RegionUtil.from_country_code_to_name(j.fetch('country')),
        latitude: 0,
        longitude: 0
      )
    end
  end
end

Seeds::SeedLegislator.run
