# typed: true

require_relative "base"

module SeedPreparers
  module Legislators
    class Sway < Base
      extend T::Sig

      sig { params(json: T::Hash[String, String], sway_locale: SwayLocale, is_internet_connected: T::Boolean).void }
      def initialize(json, sway_locale, is_internet_connected)
        super
      end

      def external_id
        @_external_id ||= json.fetch("external_id", json.fetch("externalId", nil))
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
        @_first_name ||= json.fetch("first_name", json.fetch("firstName", nil))
      end

      def last_name
        @_last_name ||= json.fetch("last_name", json.fetch("lastName", nil))
      end

      def country
        @_country ||= RegionUtil.from_country_code_to_name(json.fetch("country", "United States"))
      end

      def region_code
        @_region_code ||= RegionUtil.from_region_name_to_region_code(
          json.fetch("region_code", json.fetch("regionCode", json.fetch("region", "")))
        )
      end

      def postal_code
        @_postal_code ||= json.fetch("postal_code", json.fetch("postalCode", json.fetch("zip", json.fetch("zip_code", json.fetch("zipCode", nil)))))
      end

      def photo_url
        @_photo_url ||= json.fetch("photoURL", json.fetch("photo_url", json.fetch("photoUrl", nil)))
      end

      def congress?
        false
      end
    end
  end
end
