# frozen_string_literal: true

module LegislatorsCache
  # @lat: [[legislators-cache-departed-member-entries#Why the entry carries "currentMember" => false]]
  class DepartedMemberEntries
    # @lat: [[legislators-cache-departed-member-entries#Why the entry carries "currentMember" => false]]
    def self.for(sway_locale:, listed_bioguide_ids:)
      new(sway_locale, listed_bioguide_ids).call
    end

    def initialize(sway_locale, listed_bioguide_ids)
      @sway_locale = sway_locale
      @listed_bioguide_ids = listed_bioguide_ids
    end

    def call
      entries = still_in_office.map { |legislator| entry_for(legislator) }.compact

      SwayLogging.info(
        "legislators_cache.congress.departed_members",
        kept: entries.size,
        bioguide_ids: entries.pluck("bioguideId").first(25)
      )

      entries.sort_by { |entry| entry.fetch("bioguideId") }
    end

    private

    attr_reader :sway_locale, :listed_bioguide_ids

    # @lat: [[legislators-cache-departed-member-entries#Why the entry carries "currentMember" => false]]
    def still_in_office
      Legislator
        .where(sway_locale: sway_locale)
        .where.not(external_id: listed_bioguide_ids)
        .includes(legislator_terms: {district: :sway_locale})
        .select { |legislator| TermWindow.running_on(Date.current, legislator.legislator_terms.to_a) }
    end

    # @lat: [[legislators-cache-departed-member-entries#Why the entry carries "currentMember" => false]]
    def entry_for(legislator)
      region_code, district_number = seat_of(legislator)
      return nil if region_code.blank?

      {
        "bioguideId" => legislator.external_id,
        "name" => "#{legislator.last_name}, #{legislator.first_name}",
        "firstName" => legislator.first_name,
        "lastName" => legislator.last_name,
        # @lat: [[legislators-cache-departed-member-entries#What is and is not invented here]]
        "partyName" => legislator.party,
        "state" => RegionUtil.from_region_code_to_region_name(region_code),
        "district" => district_number,
        # @lat: [[legislators-cache-departed-member-entries#Why the entry carries "currentMember" => false]]
        "currentMember" => false,
        "url" => legislator.link,
        "addressInformation" => {"phoneNumber" => legislator.phone},
        "depiction" => {"imageUrl" => legislator.photo_url},
        "email" => legislator.email,
        "twitter" => legislator.twitter
      }
    end

    def seat_of(legislator)
      newest = legislator.legislator_terms.max_by(&:term_start_year)
      name = newest&.district&.name.to_s
      return [nil, nil] if name.blank?

      [name[/\A[A-Za-z]+/], name[/\d+\z/]]
    end
  end
end
