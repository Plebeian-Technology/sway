# typed: true

require_relative "base"

module SeedPreparers
  module Legislators
    class OpenStates < Base
      extend T::Sig

      attr_reader :json

      sig { params(json: T::Hash[String, String], sway_locale: SwayLocale).void }
      def initialize(json, sway_locale)
        super
      end

      sig { returns(District) }
      def district
        if region_code.blank?
          raise SeedErrors::MissingRegionCode.new("No regionCode attribute found in legislator json. Sway locale - #{sway_locale.name}, Legislator - #{external_id}")
        end

        # Used in sway_registration_service.district_legislators
        unless RegionUtil::STATE_CODES_NAMES.key?(region_code.to_sym)
          raise SeedErrors::NonStateRegionCode.new("regionCode must be a US state (until Sway goes international :) - Received #{region_code}")
        end

        d = (json.dig("current_role", "district").presence || "0").to_s
        name = SeedLegislator.district_name(region_code, d.remove_non_digits.to_i)

        District.find_or_create_by!(
          name:,
          sway_locale:
        )
      end

      sig { returns(T.nilable(Address)) }
      def address
        nil
      end

      def link
        json.fetch("openstates_url")
      end

      def external_id
        @_external_id ||= json.fetch("id")
      end

      def active
        true
      end

      def title
        json.dig("current_role", "title")
      end

      def party
        @_party ||= Legislator.to_party_char_from_name(json.fetch("party", "U").first)
      end

      def first_name
        json.fetch("given_name")
      end

      def last_name
        json.fetch("family_name")
      end

      def country
        @_country ||= RegionUtil.from_country_code_to_name(json.fetch("country", "United States"))
      end

      def region_code
        @_region_code ||= RegionUtil.from_region_name_to_region_code(json.dig("jurisdiction", "name"))
      end

      def postal_code
        @_postal_code ||= ""
      end

      def photo_url
        @_photo_url ||= json.fetch("image")
      end

      def congress?
        false
      end
    end
  end
end
