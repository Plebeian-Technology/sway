# frozen_string_literal: true

require "date"
require "digest"
require "json"

class OfficialEvidence
  module Readers
    # @lat: [[official-service-evidence#A retained fact proves one interval]]
    class ServiceReader
      def initialize(profile:, sway_locale: nil, connection: nil, retrieved_at: Time.current)
        @profile = profile.is_a?(Hash) ? profile.deep_symbolize_keys : {}
        @sway_locale = sway_locale
        @connection = connection
        @retrieved_at = retrieved_at
      end

      def call
        return unsupported(:profile_not_declared) unless supported_profile?

        response = connection.get(profile[:source_url].to_s)
        unless response.status.to_i.between?(200, 299)
          return source_gap(:source_request_failed, status: response.status)
        end
        return source_gap(:source_url_mismatch) unless response.env&.url&.to_s == profile[:source_url].to_s

        payload = response.body.to_s
        parsed = JSON.parse(payload)
        records = Array(extract(parsed, profile[:records_path]))
        normalized = records.filter_map { |record| normalize_record(record) }
        invalid_count = records.size - normalized.size
        evidence = persist_evidence(payload, normalized)
        facts = normalized.map { |values| fact_for(values, evidence) }
        gaps = []
        gaps << {reason: :unsupported_records, count: invalid_count} if invalid_count.positive?
        OfficialEvidence::Result.new(facts:, coverage_gaps: gaps)
      rescue Faraday::Error, JSON::ParserError
        source_gap(:source_read_failed)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        source_gap(:evidence_conflict)
      end

      private

      attr_reader :profile, :sway_locale, :retrieved_at

      def connection
        @connection ||= Faraday.new
      end

      def supported_profile?
        OfficialEvidence::SourceProfile.trusted?(profile)
      end

      def unsupported(reason)
        OfficialEvidence::Result.new(
          facts: [],
          coverage_gaps: [{reason: reason}],
          unsupported: true,
          unsupported_reason: reason
        )
      end

      def source_gap(reason, detail = {})
        OfficialEvidence::Result.new(
          facts: [],
          coverage_gaps: [{reason: reason}.merge(detail)],
          unsupported: false
        )
      end

      def extract(value, path)
        return value if path.blank? || path == "$"

        path.to_s.sub(/\A\$\.?/, "").split(".").compact_blank.reduce(value) do |current, segment|
          if current.is_a?(Array)
            current[segment.to_i]
          elsif current.is_a?(Hash)
            current[segment] || current[segment.to_sym]
          end
        end
      end

      def normalize_record(record)
        return unless record.is_a?(Hash)

        raw = profile[:fields].to_h { |key, path| [key.to_sym, extract(record, path)] }
        office_identity = raw[:office_identity]&.to_s
        return unless office_identity == profile[:office_identity].to_s
        return unless OfficialEvidence::FactPresence::ALL.include?(raw[:presence].to_s)

        if raw[:presence].to_s == OfficialEvidence::FactPresence::VACANT
          return {
            person_identity: nil,
            office_identity:,
            first_name: nil,
            last_name: nil,
            party: nil,
            chamber: raw[:chamber],
            district: raw[:district],
            title: nil,
            start_date: nil,
            end_date: nil,
            start_year: nil,
            end_year: nil,
            date_precision: OfficialEvidence::DatePrecision::NONE,
            date_semantics: profile[:date_semantics],
            presence: OfficialEvidence::FactPresence::VACANT
          }
        end

        start_date = exact_date(raw[:start_date])
        end_date = exact_date(raw[:end_date])
        return if raw[:id].blank? || raw[:title].blank? ||
          start_date.nil? || end_date.nil? || end_date <= start_date

        identity = LegislatorIdentity.from_published_id(profile[:identity_source], raw[:id])
        return unless identity

        {
          person_identity: identity,
          office_identity:,
          first_name: raw[:first_name],
          last_name: raw[:last_name],
          party: raw[:party],
          chamber: raw[:chamber],
          district: raw[:district],
          title: raw[:title].to_s,
          start_date: start_date,
          end_date: end_date,
          start_year: start_date.year,
          end_year: end_date.year,
          date_precision: OfficialEvidence::DatePrecision::EXACT,
          date_semantics: profile[:date_semantics],
          presence: raw[:presence].to_s
        }
      end

      def exact_date(value)
        return unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

        date = Date.iso8601(value)
        (date if date.iso8601 == value)
      rescue Date::Error
        nil
      end

      def persist_evidence(payload, values)
        payload_hash = Digest::SHA256.hexdigest(payload)
        parsed_values = {"facts" => values.map { |fact| normalized_hash(fact) }}
        presences = values.pluck(:presence).uniq
        precisions = values.pluck(:date_precision).uniq
        attrs = {
          publisher: profile[:publisher],
          jurisdiction: profile[:jurisdiction],
          source_url: profile[:source_url],
          external_record_id: (values.first[:person_identity]&.value if values.one?),
          sway_locale_id: sway_locale&.id,
          retrieved_at: retrieved_at,
          payload: payload,
          payload_hash: payload_hash,
          fact_type: profile[:fact_type],
          fact_presence: if presences.one?
                           presences.first
                         else
                           OfficialEvidence::FactPresence::PARTIAL
                         end,
          parsed_values: parsed_values,
          date_precision: precisions.one? ? precisions.first : OfficialEvidence::DatePrecision::NONE,
          date_semantics: profile[:date_semantics].deep_stringify_keys
        }
        existing = OfficialEvidence.find_by(payload_hash:, source_url: profile[:source_url])
        if existing
          matches = existing.parsed_values.is_a?(Hash) && existing.parsed_values.deep_stringify_keys == parsed_values &&
            existing.publisher == attrs[:publisher] &&
            existing.jurisdiction == attrs[:jurisdiction] &&
            existing.external_record_id == attrs[:external_record_id] &&
            existing.fact_type == attrs[:fact_type] &&
            existing.fact_presence == attrs[:fact_presence] &&
            existing.date_precision == attrs[:date_precision] &&
            existing.date_semantics.deep_stringify_keys == attrs[:date_semantics] &&
            existing.sway_locale_id == attrs[:sway_locale_id]
          return existing if matches
        end
        raise ActiveRecord::RecordNotUnique, "Stored evidence disagrees with normalized source facts" if existing

        OfficialEvidence.create!(**attrs)
      end

      def normalized_hash(values)
        identity = values[:person_identity]
        {
          "person_identity_source" => identity&.source,
          "person_identity_value" => identity&.value,
          "office_identity" => values[:office_identity],
          "first_name" => values[:first_name]&.to_s,
          "last_name" => values[:last_name]&.to_s,
          "party" => values[:party]&.to_s,
          "chamber" => values[:chamber]&.to_s,
          "district" => values[:district]&.to_s,
          "title" => values[:title],
          "start_date" => values[:start_date]&.iso8601,
          "end_date" => values[:end_date]&.iso8601,
          "start_year" => values[:start_year],
          "end_year" => values[:end_year],
          "date_precision" => values[:date_precision],
          "date_semantics" => values[:date_semantics].deep_stringify_keys,
          "presence" => values[:presence]
        }
      end

      def fact_for(values, evidence)
        person_identity = values[:person_identity]
        office_identity = values[:office_identity]
        OfficialEvidence::Fact.new(
          person_identity:,
          office_identity:,
          first_name: values[:first_name],
          last_name: values[:last_name],
          party: values[:party],
          chamber: values[:chamber],
          district: values[:district],
          title: values[:title],
          start_date: values[:start_date],
          end_date: values[:end_date],
          start_year: values[:start_year],
          end_year: values[:end_year],
          date_precision: values[:date_precision],
          date_semantics: values[:date_semantics],
          presence: values[:presence],
          evidence:,
          source_profile: profile,
          sway_locale_id: sway_locale&.id,
          external_record_id: evidence.external_record_id
        )
      end
    end
  end
end
