# frozen_string_literal: true

class OfficialEvidence
  # @lat: [[official-service-evidence#A retained fact proves one interval]]
  class Fact
    attr_reader :person_identity, :office_identity, :evidence, :first_name,
      :last_name, :party, :chamber, :district, :title, :start_date, :end_date,
      :start_year, :end_year, :date_precision, :date_semantics, :presence,
      :unsupported_reason, :source_profile, :external_record_id

    def initialize(
      person_identity:,
      office_identity:,
      evidence:,
      source_profile:,
      external_record_id:,
      first_name: nil,
      last_name: nil,
      party: nil,
      chamber: nil,
      district: nil,
      title: nil,
      start_date: nil,
      end_date: nil,
      start_year: nil,
      end_year: nil,
      date_precision: nil,
      date_semantics: {},
      presence: :present,
      sway_locale_id: nil,
      unsupported_reason: nil
    )
      @person_identity = person_identity
      @office_identity = office_identity&.to_s
      @evidence = evidence
      @source_profile = source_profile.is_a?(Hash) ? source_profile.deep_symbolize_keys : {}
      @external_record_id = external_record_id&.to_s
      @first_name = first_name&.to_s
      @last_name = last_name&.to_s
      @party = party&.to_s
      @chamber = chamber&.to_s
      @district = district&.to_s
      @title = title&.to_s
      @start_date = start_date
      @end_date = end_date
      @start_year = start_year
      @end_year = end_year
      @date_precision = date_precision&.to_s
      @date_semantics = date_semantics.is_a?(Hash) ? date_semantics.deep_stringify_keys.freeze : {}.freeze
      @sway_locale_id = sway_locale_id
      @presence = presence.to_s
      @unsupported_reason = unsupported_reason
    end

    def present?
      presence == OfficialEvidence::FactPresence::PRESENT
    end

    def vacant?
      presence == OfficialEvidence::FactPresence::VACANT
    end

    def exact_dates?
      date_precision == OfficialEvidence::DatePrecision::EXACT
    end

    def year_only?
      date_precision == OfficialEvidence::DatePrecision::YEAR_ONLY
    end

    def supported_title?
      present? && identity_and_title? && evidence_matches_profile? && parsed_values_match?
    end

    def supported_service?
      return false unless supported_title? && exact_dates?

      service_start = start_date
      service_end = end_date
      service_start.is_a?(Date) && service_end.is_a?(Date) && service_end > service_start &&
        date_semantics == {"start" => "inclusive", "end" => "exclusive"}
    end

    def current_member?(on: Date.current)
      return false unless supported_service?

      service_start = start_date
      service_end = end_date
      service_start.is_a?(Date) && service_end.is_a?(Date) && service_start <= on && on < service_end
    end

    def normalized_values
      {
        "person_identity_source" => person_identity&.source,
        "person_identity_value" => person_identity&.value,
        "office_identity" => office_identity,
        "first_name" => first_name,
        "last_name" => last_name,
        "party" => party,
        "chamber" => chamber,
        "district" => district,
        "title" => title,
        "start_date" => start_date&.iso8601,
        "end_date" => end_date&.iso8601,
        "start_year" => start_year,
        "end_year" => end_year,
        "date_precision" => date_precision,
        "date_semantics" => date_semantics,
        "presence" => presence
      }
    end

    private

    def identity_and_title?
      person_identity.is_a?(LegislatorIdentity) &&
        person_identity.source == source_profile[:identity_source].to_s &&
        person_identity.value.present? && office_identity.present? && title.present?
    end

    def evidence_matches_profile?
      return false unless evidence.is_a?(OfficialEvidence) && evidence.persisted?
      return false if evidence.changed?
      return false unless OfficialEvidence::SourceProfile.trusted?(source_profile)
      return false unless evidence.payload_hash == Digest::SHA256.hexdigest(evidence.payload.to_s)
      return false unless evidence.fact_type == source_profile[:fact_type].to_s

      evidence.publisher == source_profile[:publisher].to_s &&
        evidence.jurisdiction == source_profile[:jurisdiction].to_s &&
        evidence.source_url == source_profile[:source_url].to_s &&
        evidence.fact_type == source_profile[:fact_type].to_s &&
        evidence.sway_locale_id == @sway_locale_id &&
        evidence.date_semantics.is_a?(Hash) &&
        evidence.date_semantics.deep_stringify_keys == date_semantics &&
        evidence_summary_matches? &&
        [nil, person_identity&.value].include?(evidence.external_record_id)
    rescue NoMethodError, TypeError
      false
    end

    def parsed_values_match?
      return false unless evidence.parsed_values.is_a?(Hash)

      values = evidence.parsed_values.deep_stringify_keys
      Array(values["facts"]).any? do |retained|
        next false unless retained.is_a?(Hash)

        retained_values = retained.deep_stringify_keys
        retained_values == normalized_values &&
          (external_record_id.nil? || retained_values["person_identity_value"] == external_record_id)
      end
    rescue NoMethodError, TypeError
      false
    end

    def evidence_summary_matches?
      retained_facts = evidence.parsed_values.deep_stringify_keys.fetch("facts")
      return false unless retained_facts.is_a?(Array)

      presences = retained_facts.filter_map { |retained| retained["presence"] if retained.is_a?(Hash) }.uniq
      precisions = retained_facts.filter_map { |retained| retained["date_precision"] if retained.is_a?(Hash) }.uniq
      expected_presence = presences.one? ? presences.first : OfficialEvidence::FactPresence::PARTIAL
      expected_precision = precisions.one? ? precisions.first : OfficialEvidence::DatePrecision::NONE
      evidence.fact_presence == expected_presence && evidence.date_precision == expected_precision
    end
  end
end
