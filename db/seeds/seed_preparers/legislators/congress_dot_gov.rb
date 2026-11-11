require_relative "base"

module SeedPreparers
  module Legislators
    class CongressDotGov < Base
      def external_id
        @external_id ||= json.fetch("bioguideId")
      end

      # The bioguide id names a person and keeps naming them across every
      # re-election and every change of chamber, so it is the whole identity.
      def identity
        LegislatorIdentity.from_published_id(LegislatorIdentity::BIOGUIDE, external_id)
      end

      def current_member?
        json.fetch("currentMember", true)
      end

      # @lat: [[seed-legislator-terms-add-correct-retire#The termsSource mark and its shape check (congress.gov)]]
      def terms_from_history?
        return false unless sway_locale.term_rules.publishes_term_history
        return false if json["termsSource"].blank?

        items = Array(json.dig("terms", "item"))
        items.any? && items.all? { |item| item["endYear"].present? }
      end

      def title
        title_for_chamber(current_term&.fetch("chamber", nil))
      end

      def district
        @district ||= current_term_row&.fetch(:district, nil) || super
      end

      # @lat: [[representative-resolution#Congress seat identity conventions]]
      def current_office_identity
        return nil if executive? || potus?
        return nil unless current_member?

        state = (current_term&.fetch("stateCode", nil) || region_code)&.downcase
        return nil if state.blank?

        chamber = current_term&.fetch("chamber", nil) || ((title == "Sen.") ? "Senate" : "House of Representatives")

        case chamber
        when "Senate"
          senate_class = current_term&.fetch("class", nil)
          return nil if senate_class.blank? || !senate_class.to_i.between?(1, 3)

          "#{state}-senate-class-#{senate_class.to_i}"
        when "House", "House of Representatives"
          dist_num = (current_term&.fetch("district", nil) || json.fetch("district", nil) || 0).to_s.remove_non_digits.to_i
          "#{state}-house-district-#{dist_num}"
        end
      end

      def party
        return @party if @party.present?

        par =
          json.fetch(
            "partyName",
            json.dig("partyHistory", 0, "partyAbbreviation")
          )
        if par.blank?
          par =
            if current_term&.fetch("chamber", nil) == "Senate"
              "Sen."
            else
              "Rep."
            end
        end

        @party ||= Legislator.to_party_char_from_name(par)
      end

      # Returns the NEWEST term's start year.
      # @lat: [[congress-term-history-unbroken-service#Picking the current term: max_by, not position]]
      def term_start_year
        @term_start_year ||=
          current_term_row&.fetch(:term_start_year) ||
          (Date.current.year.odd? ? Date.current.year : Date.current.year - 1)
      end

      # Returns the end year of the same term #term_start_year reports. Falls
      # back to term_start_year plus the chamber's term length so the result is
      # always non-nil.
      def term_end_year
        @term_end_year ||=
          current_term_row&.fetch(:term_end_year) ||
          (term_start_year + chamber_term_length)
      end

      # @lat: [[congress-term-history-unbroken-service#authoritative_term?]]
      def authoritative_term?
        current_term&.fetch("startYear", nil).present?
      end

      # @lat: [[seed-legislator-terms-add-correct-retire#Why the default proven_terms is per-locale]]
      def proven_terms
        Array(json.dig("terms", "item")).filter_map { |item| term_from(item) }
      end

      # By design, the President (and, if ever seeded, a VP) never gets a
      # scoreable LegislatorTerm — only a Legislator person row.
      def executive?
        potus?
      end

      def first_name
        json.fetch(
          "first_name",
          json.fetch(
            "firstName",
            json.fetch("name", "").split(",").last&.strip
          )
        )
      end

      def last_name
        json.fetch(
          "last_name",
          json.fetch(
            "lastName",
            json.fetch("name", "").split(",").first&.strip
          )
        )
      end

      def phone
        json.dig("addressInformation", "phoneNumber")
      end

      def link
        default_link = "https://api.congress.gov/v3/member/#{external_id}"
        json.fetch("url", json.fetch("officialWebsiteUrl", default_link)) ||
          default_link
      end

      def country
        @country ||=
          RegionUtil.from_country_code_to_name(
            json.fetch("country", "United States")
          )
      end

      def region_code
        @region_code ||=
          if potus?
            json.fetch("state")
          else
            RegionUtil.from_region_name_to_region_code(json.fetch("state"))
          end
      end

      def postal_code
        @postal_code ||= json.dig("addressInformation", "zipCode") || "20004" # US Capitol
      end

      def photo_url
        @photo_url ||= json.dig("depiction", "imageUrl")
      end

      def congress?
        true
      end

      def potus?
        external_id == "POTUS" # set by Sway
      end

      private

      # The term row the NEWEST terms.item entry stands for, or nil when the
      # blob carries no usable entry. Held so #term_start_year and
      # #term_end_year always report the two ends of the SAME term.
      def current_term_row
        return @current_term_row if defined?(@current_term_row)

        @current_term_row = term_from(current_term)
      end

      # Turns one terms.item entry into the term it stands for, or nil when the
      # entry carries no start year and so proves nothing.
      # @lat: [[congress-term-history-unbroken-service#Picking the current term: max_by, not position]]
      def term_from(item)
        return nil if item.nil?

        start_year = item["startYear"]&.to_i
        return nil if start_year.blank?

        item_title = title_for_chamber(item["chamber"])
        years_long = chamber_term_length_for(item_title)
        end_year = item["endYear"]&.to_i

        if end_year.nil?
          start_year = TermWindow.running_term_start_year(sway_locale, start_year, years_long)
          end_year = start_year + years_long
        end

        {
          term_start_year: start_year,
          term_end_year: end_year,
          title: item_title,
          # @lat: [[current-legislator-term#Which term a legislator is serving now#A term carries the day it really began]]
          began_on: parsed_began_on(item),
          ended_on: parsed_ended_on(item),
          district: district_for(item["stateCode"], item["district"])
        }
      end

      # The published start DATE of one term, or nil. What tells a mid-cycle
      # successor apart from somebody seated at the January handover.
      def parsed_began_on(item)
        raw = item["beganOn"]
        return nil if raw.blank?

        Date.parse(raw.to_s)
      rescue ArgumentError, TypeError
        SwayLogging.warn(
          "congress_dot_gov.unreadable_began_on", external_id: external_id, value: raw.to_s
        )
        nil
      end

      # The published end DATE of one term, or nil. Never invented: a term with
      # no date reads as running to the locale's handover day, which is what
      # every term did before this.
      def parsed_ended_on(item)
        raw = item["endedOn"]
        return nil if raw.blank?

        Date.parse(raw.to_s)
      rescue ArgumentError, TypeError
        SwayLogging.warn(
          "congress_dot_gov.unreadable_ended_on", external_id: external_id, value: raw.to_s
        )
        nil
      end

      # @lat: [[congress-term-history-unbroken-service#Picking the current term: max_by, not position]]
      def current_term
        @current_term ||=
          json.dig("terms", "item")
            &.then { |items| Array(items).max_by { |t| t["startYear"].to_i } }
      end

      # Term length in years by chamber, for the CURRENT term's title.
      def chamber_term_length
        chamber_term_length_for(title)
      end

      # Term length in years for any resolved title. Used by #proven_terms,
      # where each terms.item entry resolves its own title, which can differ
      # from the CURRENT term's — for example after a House-to-Senate move.
      def chamber_term_length_for(resolved_title)
        CongressChamber.term_years_for(resolved_title)
      end

      # Resolves a terms.item entry's title from that entry's own "chamber"
      # key. Every entry becomes "Sen." or "Rep." based on its OWN chamber, not
      # the legislator's current one — a House-to-Senate mover's earlier
      # entries report the chamber they actually served in at the time.
      def title_for_chamber(chamber)
        CongressChamber.title_for(chamber, president: potus?)
      end
    end
  end
end
