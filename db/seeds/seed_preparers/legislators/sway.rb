require_relative "base"

module SeedPreparers
  module Legislators
    class Sway < Base
      # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars]]

      def external_id
        @external_id ||=
          json.fetch("external_id", json.fetch("externalId", nil))&.to_s
      end

      # @lat: [[legislator-person-not-seat#external_id means different things per source]]
      def identity
        case sway_locale.term_rules.identified_by
        when :seat
          LegislatorIdentity.seat_and_name(
            seat: external_id,
            first_name: first_name,
            last_name: last_name
          )
        when :person
          LegislatorIdentity.from_published_id(LegislatorIdentity::CURATED_PERSON, external_id)
        else
          raise SeedErrors::UnknownIdentityScheme,
            "SwayLocale #{sway_locale.name.inspect} declares identified_by " \
            "#{sway_locale.term_rules.identified_by.inspect}, which no preparer reads. " \
            "Say :person when the roster names people and :seat when it names offices."
        end
      end

      # @lat: [[representative-resolution#Configured seat identity for person-keyed rosters#Curated person-keyed rosters]]
      def current_office_identity
        external_id
      end

      # Defaults to true. This reader used to be dead code, and it is now called
      # for every entry on every boot, so a roster written without the key would
      # raise KeyError, fail the seed, and leave the container unable to start.
      def current_member?
        json.fetch("active", true)
      end

      def title
        json.fetch("title")
      end

      def party
        @party ||= Legislator.to_party_char_from_name(json.fetch("party", nil))
      end

      def first_name
        @first_name ||= json.fetch("first_name", json.fetch("firstName", nil))
      end

      def last_name
        @last_name ||= json.fetch("last_name", json.fetch("lastName", nil))
      end

      def country
        @country ||=
          RegionUtil.from_country_code_to_name(
            json.fetch("country", "United States")
          )
      end

      def region_code
        @region_code ||=
          RegionUtil.from_region_name_to_region_code(
            json.fetch(
              "region_code",
              json.fetch("regionCode", json.fetch("region", ""))
            )
          )
      end

      def postal_code
        @postal_code ||=
          json.fetch(
            "postal_code",
            json.fetch(
              "postalCode",
              json.fetch(
                "zip",
                json.fetch("zip_code", json.fetch("zipCode", nil))
              )
            )
          )
      end

      def photo_url
        @photo_url ||=
          json.fetch(
            "photoURL",
            json.fetch("photo_url", json.fetch("photoUrl", nil))
          )
      end

      # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars]]
      def term_start_year
        @term_start_year ||=
          json.fetch("term_start_year", json.fetch("termStartYear", nil))&.to_i ||
          current_cycle_start_year
      end

      # Returns the term end year as a non-nil Integer. Checks both key
      # spellings; falls back to term_start_year + cycle_years.
      def term_end_year
        @term_end_year ||=
          json.fetch("term_end_year", json.fetch("termEndYear", nil))&.to_i ||
          (term_start_year + cycle_years)
      end

      # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster evidence for observed departures]]
      def authoritative_term?
        json.fetch("term_start_year", json.fetch("termStartYear", nil)).present?
      end

      def congress?
        false
      end

      private

      # Stable election-cycle start year via integer floor division.
      def current_cycle_start_year
        cycle_anchor_year +
          cycle_years *
            ((Date.current.year - cycle_anchor_year) / cycle_years)
      end

      def cycle_anchor_year
        sway_locale.term_rules.cycle_anchor_year
      end

      def cycle_years
        sway_locale.term_rules.cycle_years
      end
    end
  end
end
