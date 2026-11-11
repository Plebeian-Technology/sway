require_relative "base"

module SeedPreparers
  module Legislators
    class OpenStates < Base
      TITLE_ALIASES = {"State Delegate" => "Delegate", "State Senator" => "Senator"}.freeze

      attr_reader :json

      def initialize(json, sway_locale, roster: nil)
        super(json, sway_locale)
        @roster = roster
      end

      # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars]]

      def district
        if region_code.blank?
          raise SeedErrors::MissingRegionCode,
            "No region_code attribute found in legislator json. Sway locale - #{sway_locale.name}, Legislator - #{external_id}"
        end

        # Used in sway_registration_service.district_legislators
        unless RegionUtil::STATE_CODES_NAMES.key?(region_code.to_sym)
          raise SeedErrors::NonStateRegionCode,
            "region_code must be a US state (until Sway goes international :) - Received #{region_code}"
        end

        d = (json.dig("current_role", "district").presence || "0").to_s
        name =
          SeedLegislator.district_name(region_code, d.remove_non_digits.to_i)

        District.find_or_create_by!(name:, sway_locale:)
      end

      def address
        nil
      end

      def link
        json.fetch("openstates_url", json.fetch("openstatesUrl", nil))
      end

      def external_id
        @external_id ||= json.fetch("id")
      end

      # An ocd-person id names a person, not a district, and OpenStates keeps
      # it across a move between chambers. Every state roster reads this way,
      # so a state added later needs nothing new here.
      def identity
        LegislatorIdentity.from_published_id(LegislatorIdentity::OPENSTATES, external_id)
      end

      def current_member?
        true
      end

      def title
        raw = json.dig("current_role", "title")
        (raw == "Lt. Governor") ? "Lt_Governor" : raw
      end

      def canonical_title(raw = title)
        TITLE_ALIASES.fetch(raw, raw)
      end

      # @lat: [[representative-resolution#Maryland seat identity conventions#Executive offices without a configured chamber]]
      def executive_office?
        json.dig("current_role", "org_classification") == "executive"
      end

      # @lat: [[representative-resolution#Maryland seat identity conventions]]
      def current_office_identity
        case canonical_title
        when "Governor", "Lt_Governor", "Attorney General"
          "#{region_code.downcase}-#{normalized_title}-0"
        when "Senator"
          d_num = (json.dig("current_role", "district").presence || "0").to_s.remove_non_digits.to_i
          "#{region_code.downcase}-senator-#{d_num}"
        when "Delegate"
          delegate_office_identity
        end
      end

      def party
        @party ||=
          Legislator.to_party_char_from_name(json.fetch("party", "U").first)
      end

      def first_name
        json.fetch("given_name")
      end

      def last_name
        json.fetch("family_name")
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
            json.dig("jurisdiction", "name")
          )
      end

      def postal_code
        @postal_code ||= ""
      end

      def photo_url
        @photo_url ||= json.fetch("image")
      end

      # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars]]
      def term_start_year
        @term_start_year ||=
          json.dig("current_role", "start_date")&.to_date&.year ||
          current_cycle_start_year
      end

      # Returns the term end year as a non-nil Integer. Reads the year of
      # current_role.end_date when present; otherwise falls back to
      # term_start_year + cycle_years, so the result is always
      # non-nil.
      def term_end_year
        @term_end_year ||=
          json.dig("current_role", "end_date")&.to_date&.year ||
          (term_start_year + cycle_years)
      end

      # True only when current_role.start_date is present — a real source
      # year exists. False for all live Maryland entries today, so
      # #proven_terms (the Base default) never reports the cycle-anchor
      # fallback as a proven term.
      def authoritative_term?
        json.dig("current_role", "start_date").present?
      end

      def congress?
        false
      end

      def self.cached_roster_for(path)
        @cached_rosters ||= {}
        @cached_rosters[path] ||= JSON.parse(File.read(path))
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

      def normalized_title
        title.to_s.strip.downcase.tr("_ ", "--").squeeze("-")
      end

      def delegate_office_identity
        raw_district = (json.dig("current_role", "district") || "").to_s.strip
        d_key = raw_district.downcase
        reg = region_code.downcase

        explicit_slot = json["slot"] || json.dig("current_role", "slot")
        return "#{reg}-delegate-#{d_key}-#{explicit_slot}" if explicit_slot

        cohort = matching_delegate_cohort(raw_district)
        if cohort.size > 1 || raw_district =~ /^[0-9]+$/
          sorted = cohort.sort_by { |e| e.fetch("id") }
          index = sorted.index { |e| e["id"] == external_id }
          slot = index ? index + 1 : 1
          "#{reg}-delegate-#{d_key}-#{slot}"
        else
          "#{reg}-delegate-#{d_key}"
        end
      end

      def matching_delegate_cohort(raw_district)
        cohort = candidate_roster.select do |entry|
          role = entry["current_role"] || {}
          canonical_title(role["title"]) == "Delegate" && (role["district"] || "").to_s.strip.casecmp?(raw_district)
        end
        cohort = [json] if cohort.empty?
        cohort << json if cohort.none? { |e| e["id"] == external_id }
        cohort
      end

      def candidate_roster
        return @roster if @roster

        if sway_locale
          file = "db/seeds/data/#{sway_locale.reversed_name.tr("-", "/")}/legislators.json"
          return self.class.cached_roster_for(file) if File.exist?(file)
        end

        []
      end
    end
  end
end
