# frozen_string_literal: true

# @lat: [[current-legislator-term#Which term a legislator is serving now#Planned automatic legislator updates#Officially supported title completion]]
class ExecutiveTitleFillService
  def initialize(sway_locale, official_service_result:)
    @sway_locale = sway_locale
    @official_service_result = official_service_result
  end

  def call
    return unless official_service_result.is_a?(OfficialEvidence::Result)
    return unless official_service_result.supported?

    fact_pairs = official_service_result.facts.filter_map do |fact|
      next unless fact.is_a?(OfficialEvidence::Fact) && fact.supported_service?
      next unless fact.evidence&.sway_locale_id == sway_locale.id

      identity = fact.person_identity
      next unless identity.is_a?(LegislatorIdentity)

      [[identity.source, identity.value], fact]
    end
    facts_by_identity = fact_pairs.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    identities_by_key = LegislatorIdentifier
      .includes(legislator: [:legislator_identifiers, {legislator_terms: [:district, :seat]}])
      .where(
        sway_locale_id: sway_locale.id,
        source: facts_by_identity.keys.map(&:first).uniq,
        value: facts_by_identity.keys.map(&:last).uniq
      )
      .index_by { |identifier| [identifier.source, identifier.value] }

    facts_by_identity.each do |(source, value), facts|
      legislator = identities_by_key[[source, value]]&.legislator
      next unless legislator

      facts.group_by { |fact| [fact.office_identity, fact.district, fact.start_date, fact.end_date] }.each_value do |matching_facts|
        next unless matching_facts.one?

        fact = matching_facts.first
        term = legislator.legislator_terms.find do |candidate|
          candidate.title.blank? && candidate.seat&.seat_identifier == fact.office_identity &&
            candidate.district.name == fact.district && candidate.began_on == fact.start_date &&
            candidate.ended_on == fact.end_date
        end
        next unless term

        prepared = OfficialEvidence::PreparedServiceEntry.new(
          official_fact: fact,
          official_service_result: official_service_result,
          district: term.district
        )
        SeedLegislatorTerms.fill_missing_title!(term, prepared:)
      end
    end
  end

  private

  attr_reader :sway_locale, :official_service_result
end
