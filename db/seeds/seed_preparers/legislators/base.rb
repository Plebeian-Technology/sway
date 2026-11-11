require_relative "../../seed_errors"

module SeedPreparers
  module Legislators
    class Base
      attr_reader :json, :sway_locale

      def initialize(json, sway_locale)
        @sway_locale = sway_locale
        @json = json
      end

      # The seat this legislator holds RIGHT NOW.
      def district
        @district ||= begin
          if region_code.blank?
            raise SeedErrors::MissingRegionCode,
              "No region_code attribute found in legislator json. Sway locale - #{sway_locale.name}, Legislator - #{external_id}"
          end

          district_for(region_code, json.fetch("district", nil))
        end
      end

      # The District row for one seat, named by its state and its number.
      # @lat: [[seed-legislator-terms-add-correct-retire#Why CORRECT never touches the seat]]
      def district_for(region_code, number)
        return nil if region_code.blank?

        # Used in sway_registration_service.district_legislators
        unless RegionUtil::STATE_CODES_NAMES.key?(region_code.to_sym)
          raise SeedErrors::NonStateRegionCode,
            "region_code must be a US state (until Sway goes international :) - Received #{region_code}"
        end

        d = (number.presence || "0").to_s
        name = SeedLegislator.district_name(region_code, d.remove_non_digits.to_i)

        District.find_or_create_by!(name:, sway_locale:)
      end

      def phone
        json.fetch("phone", nil)
      end

      def email
        json.fetch("email", nil)
      end

      def twitter
        json.fetch("twitter", nil)
      end

      def link
        json.fetch("link", nil)
      end

      ##################################################
      #
      # Overrides
      #
      ##################################################

      def external_id
        raise NotImplementedError
      end

      # @lat: [[legislator-person-not-seat#No default_scope]]
      def identity
        raise NotImplementedError
      end

      # True when the source still lists this person as holding office.
      # @lat: [[seed-legislator-terms-add-correct-retire#Why ADD skips the current term for a departed member]]
      def current_member?
        raise NotImplementedError
      end

      def title
        raise NotImplementedError
      end

      def party
        raise NotImplementedError
      end

      def first_name
        raise NotImplementedError
      end

      def last_name
        raise NotImplementedError
      end

      def country
        "United States"
      end

      def region_code
        raise NotImplementedError
      end

      def postal_code
        raise NotImplementedError
      end

      def photo_url
        raise NotImplementedError
      end

      # Term extraction (REQUIRED — abstract, must override)
      # @lat: [[legislator-term-preparer-hard-contract#Why preparer term-year methods can never return nil]]

      # Returns the CURRENT term's start year as a non-nil Integer.
      def term_start_year
        raise NotImplementedError
      end

      # Returns the CURRENT term's end year as a non-nil Integer.
      def term_end_year
        raise NotImplementedError
      end

      # @lat: [[legislator-term-preparer-hard-contract#Why preparer term-year methods can never return nil]]
      def authoritative_term?
        raise NotImplementedError
      end

      # @lat: [[seed-legislator-terms-add-correct-retire#Why the default proven_terms is per-locale]]
      def proven_terms
        return [] unless authoritative_term?

        [{term_start_year: term_start_year, term_end_year: term_end_year, title: title}]
      end

      # @lat: [[seed-legislator-terms-add-correct-retire#Why the default proven_terms is per-locale]]
      def terms_from_history?
        false
      end

      # By design, Presidents and VPs get a Legislator person row but never a
      # scoreable LegislatorTerm. Only CongressDotGov's roster can contain an
      # executive; every other preparer is non-executive by construction.
      def executive?
        false
      end

      def congress?
        false
      end
    end
  end
end
