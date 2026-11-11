# frozen_string_literal: true

module LegislatorsCache
  # @lat: [[legislators-cache-congress-term-history#Why terms_of answers for nobody whose record could not be read whole]]
  class CongressTermHistory
    CURRENT_FILE = "legislators-current.json"
    HISTORICAL_FILE = "legislators-historical.json"

    # @lat: [[seed-legislator-terms-add-correct-retire#The termsSource mark and its shape check (congress.gov)]]
    SOURCE_NAME = "unitedstates/congress-legislators"

    SENATE_CHAMBER = "Senate"
    HOUSE_CHAMBER = "House of Representatives"
    SENATOR_TYPE = "sen"

    class FetchError < StandardError
    end

    class << self
      # @lat: [[legislators-cache-congress-term-history#Why terms_of answers for nobody whose record could not be read whole]]
      def fetch(bioguide_ids, connection: nil)
        wanted = bioguide_ids.compact.to_set
        conn = connection || Sway::FaradayStack.congress_legislators

        by_bioguide_id = index(read(conn, CURRENT_FILE), wanted)

        unanswered = wanted - by_bioguide_id.keys
        by_bioguide_id.merge!(index(read(conn, HISTORICAL_FILE), unanswered)) if unanswered.any?

        new(by_bioguide_id, missing: (wanted - by_bioguide_id.keys).to_a.sort)
      end

      private

      def read(connection, file_name)
        response = connection.get(file_name)

        unless response.status.between?(200, 299)
          raise FetchError,
            "congress-legislators returned #{response.status} fetching #{file_name}: " \
            "#{response.body.to_s[0, 300]}"
        end

        JSON.parse(response.body)
      end

      def index(entries, wanted)
        return {} if wanted.empty?

        entries.each_with_object({}) do |entry, found|
          bioguide_id = entry.dig("id", "bioguide")
          next unless wanted.include?(bioguide_id)

          terms = terms_of(entry)
          found[bioguide_id] = terms if terms.any?
        end
      end

      # @lat: [[legislators-cache-congress-term-history#Why terms_of answers for nobody whose record could not be read whole]]
      def terms_of(entry)
        published = Array(entry["terms"])
        windows = published.filter_map { |term| window(term) }
        return [] if windows.size < published.size

        keep_distinct(windows)
          .sort_by { |w| w.fetch(:start_year) }
          .map { |w| to_roster_entry(w) }
      end

      # @lat: [[retire-departed-members-safety-design#Why a stored term widens to hold a real end date, instead of narrowing]]
      def window(term)
        starts_on = Date.parse(term["start"].to_s)
        ends_on = Date.parse(term["end"].to_s)

        {
          start_year: (starts_on < january_of(starts_on.year)) ? starts_on.year - 1 : starts_on.year,
          end_year: (ends_on > january_of(ends_on.year)) ? ends_on.year + 1 : ends_on.year,
          # @lat: [[seed-legislator-terms-add-correct-retire#The termsSource mark and its shape check (congress.gov)]]
          began_on: starts_on,
          ended_on: ends_on,
          days_served: (ends_on - starts_on).to_i,
          senate: term["type"] == SENATOR_TYPE,
          senate_class: (term["type"] == SENATOR_TYPE && term["class"].present?) ? term["class"].to_i : nil,
          state_code: term["state"],
          district: term["district"]
        }
      # @lat: [[legislators-cache-congress-term-history#Why window rescues ArgumentError rather than Date::Error]]
      rescue ArgumentError, TypeError
        nil
      end

      # @lat: [[legislators-cache-congress-term-history#Why terms_of answers for nobody whose record could not be read whole]]
      def keep_distinct(windows)
        windows
          .sort_by { |w| [-w.fetch(:days_served), w.fetch(:start_year)] }
          .each_with_object([]) do |candidate, kept|
            covered = kept.any? { |k|
              k.fetch(:start_year) <= candidate.fetch(:start_year) &&
                candidate.fetch(:end_year) <= k.fetch(:end_year)
            }
            kept << candidate unless covered
          end
      end

      # @lat: [[seed-legislator-terms-add-correct-retire#Why CORRECT never touches the seat]]
      def to_roster_entry(window)
        entry = {
          "chamber" => window.fetch(:senate) ? SENATE_CHAMBER : HOUSE_CHAMBER,
          "startYear" => window.fetch(:start_year),
          "endYear" => window.fetch(:end_year),
          # @lat: [[seed-legislator-terms-add-correct-retire#The termsSource mark and its shape check (congress.gov)]]
          "beganOn" => window.fetch(:began_on).iso8601,
          "endedOn" => window.fetch(:ended_on).iso8601,
          "stateCode" => window.fetch(:state_code)
        }
        district = window.fetch(:district)
        entry["district"] = district unless district.nil?
        senate_class = window[:senate_class]
        entry["class"] = senate_class unless senate_class.nil?
        entry
      end

      # @lat: [[legislators-cache-congress-term-history#Why terms_of answers for nobody whose record could not be read whole]]
      def january_of(year)
        SwayLocale::TermRulesRegistry
          .fetch(SwayLocale::TermRulesRegistry::CONGRESS_LOCALE_NAME)
          .convening
          .date_in(year)
      end
    end

    # @lat: [[legislators-cache-congress-term-history#Why terms_of answers for nobody whose record could not be read whole]]
    attr_reader :missing

    def initialize(by_bioguide_id, missing: [])
      @by_bioguide_id = by_bioguide_id
      @missing = missing
    end

    def terms_for(bioguide_id)
      @by_bioguide_id[bioguide_id]
    end
  end
end
