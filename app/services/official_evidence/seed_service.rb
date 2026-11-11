# frozen_string_literal: true

class OfficialEvidence
  # @lat: [[official-service-evidence#Civic writes use the existing term path]]
  class SeedService
    def initialize(sway_locale:, result:)
      @sway_locale = sway_locale
      @result = result
    end

    def call
      return result if result.unsupported?

      gaps = result.coverage_gaps.dup
      ambiguous = ambiguous_offices
      ambiguous.each do |(_, office_identity)|
        gaps << {reason: :ambiguous_office_service, office_identity:}
      end
      facts_to_seed.each do |fact|
        next if fact.vacant?
        next if ambiguous.include?([fact.district, fact.office_identity])
        next unless fact.supported_service?

        district = District.find_by(sway_locale_id: sway_locale.id, name: fact.district)
        unless district && seedable?(fact, district)
          gaps << {reason: :unsupported_civic_record, office_identity: fact.office_identity}
          next
        end

        begin
          seed_fact!(fact, district)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, Seat::IdentityConflictError => error
          gaps << {reason: :civic_write_failed, office_identity: fact.office_identity, error: error.class.name}
        rescue ConflictingTerm
          gaps << {reason: :conflicting_existing_term, office_identity: fact.office_identity}
        end
      end

      OfficialEvidence::Result.new(
        facts: result.facts,
        coverage_gaps: gaps,
        unsupported: result.unsupported?,
        unsupported_reason: result.unsupported_reason
      )
    end

    private

    class ConflictingTerm < StandardError; end

    attr_reader :sway_locale, :result

    def facts_to_seed
      result.facts.select { |fact| fact.is_a?(OfficialEvidence::Fact) && fact.supported_service? }
        .uniq { |fact| [fact.normalized_values, provenance_key(fact)] }
    end

    def ambiguous_offices
      facts_to_seed.group_by { |fact| [fact.district, fact.office_identity] }.each_with_object([]) do |((_, office_identity), facts), ambiguous|
        conflicting_overlap = facts.combination(2).any? do |left, right|
          intervals_overlap?(left, right) && !same_fact?(left, right)
        end
        ambiguous << [facts.first.district, office_identity] if conflicting_overlap
      end
    end

    def intervals_overlap?(left, right)
      left_start = left.start_date
      left_end = left.end_date
      right_start = right.start_date
      right_end = right.end_date
      return false unless left_start.is_a?(Date) && left_end.is_a?(Date) && right_start.is_a?(Date) && right_end.is_a?(Date)

      left_start < right_end && right_start < left_end
    end

    def same_fact?(left, right)
      left.normalized_values == right.normalized_values && provenance_key(left) == provenance_key(right)
    end

    def provenance_key(fact)
      [fact.source_profile, fact.evidence.publisher, fact.evidence.jurisdiction,
        fact.evidence.source_url, fact.evidence.sway_locale_id]
    end

    def seedable?(fact, district)
      district.present? && district.name == fact.district &&
        district.sway_locale_id == sway_locale.id &&
        fact.first_name.present? && fact.last_name.present? &&
        fact.title.present? && fact.chamber.present? &&
        fact.office_identity.present? && fact.person_identity.present? &&
        fact.evidence.sway_locale_id == sway_locale.id
    end

    def seed_fact!(fact, district)
      identity = fact.person_identity || raise(ConflictingTerm)
      start_date = fact.start_date
      end_date = fact.end_date
      raise ConflictingTerm unless start_date.is_a?(Date) && end_date.is_a?(Date)

      Legislator.transaction do
        legislator = LegislatorIdentifier.legislator_for(sway_locale:, identity:)
        unless legislator
          legislator = Legislator.create!(
            sway_locale:,
            external_id: identity.to_s,
            first_name: fact.first_name,
            last_name: fact.last_name,
            party: fact.party.to_s,
            last_seeded_at: Time.current
          )
          LegislatorIdentifier.record!(legislator:, identity:)
        end

        existing_term = if start_date.is_a?(Date)
          LegislatorTerm.find_by(legislator:, term_start_year: start_date.year)
        else
          raise ConflictingTerm
        end
        raise ConflictingTerm unless compatible_term?(existing_term, fact, district)

        prepared = OfficialEvidence::PreparedServiceEntry.from_fact(
          fact:,
          result:,
          district:
        )
        SeedLegislatorTerms.new(legislator, prepared).call
      end
    end

    def compatible_term?(term, fact, district)
      return true unless term
      start_date = fact.start_date
      end_date = fact.end_date
      return false unless start_date.is_a?(Date) && end_date.is_a?(Date)
      return false unless term.district_id == district.id
      return false unless term.seat&.seat_identifier == fact.office_identity
      return false unless term.district.sway_locale_id == district.sway_locale_id
      return false unless term.term_end_year == end_date.year
      return false unless term.began_on == start_date && term.began_on_source == LegislatorTerm::DateSource::PUBLISHED
      return false unless term.ended_on == end_date && term.ended_on_source == LegislatorTerm::DateSource::PUBLISHED

      true
    end
  end
end
