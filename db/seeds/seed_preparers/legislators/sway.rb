# typed: true

require_relative "base"

module SeedPreparers
  module Legislators
    class Sway < Base
      extend T::Sig

      sig { params(json: T::Hash[String, String], sway_locale: SwayLocale).void }
      def initialize(json, sway_locale)
        super
      end

      sig { returns(Address) }
      def address
        a = Address.find_or_initialize_by(
          street: json.fetch("street"),
          city: json.fetch("city", "").titleize,
          region_code: region_code,
          postal_code:,
          country: country
        )

        a.street2 = json.fetch("street2", json.fetch("street_2", nil))
        a.latitude = 0.0 if a.latitude.blank?
        a.longitude = 0.0 if a.longitude.blank?

        a.save!
        a
      end

      def external_id
        @_external_id ||= json.fetch("externalId", json.fetch("external_id", nil))
      end

      def active
        json.fetch("active")
      end

      def title
        json.fetch("title")
      end

      def party
        @_party ||= Legislator.to_party_char_from_name(json.fetch("party", nil))
      end

      def first_name
        @_first_name ||= json.fetch("firstName", json.fetch("first_name", nil))
      end

      def last_name
        @_last_name ||= json.fetch("lastName", json.fetch("last_name", nil))
      end

      def country
        @_country ||= RegionUtil.from_country_code_to_name(json.fetch("country", "United States"))
      end

      def region_code
        @_region_code ||= RegionUtil.from_region_name_to_region_code(
          json.fetch("regionCode", json.fetch("region_code", json.fetch("region", "")))
        )
      end

      def postal_code
        @_postal_code ||= json.fetch("postalCode", json.fetch("postal_code", json.fetch("zip", json.fetch("zip_code", json.fetch("zipCode", nil)))))
      end

      def photo_url
        @_photo_url ||= json.fetch("photoURL", json.fetch("photoUrl", json.fetch("photo_url", nil)))
      end

      def congress?
        false
      end
    end
  end
end
