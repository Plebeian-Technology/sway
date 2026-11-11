# frozen_string_literal: true

module LegislatorsCache
  # @lat: [[current-legislator-term#Refresh comparison and publication]]
  class BaseRefresh
    include SwayGoogleCloudStorage

    BUCKET_NAME = SwayGoogleCloudStorage::BUCKETS[:ASSETS]

    class Result < Data.define(:changed_files)
    end

    def initialize(sway_locale, force: false, adapter: nil, connection: nil)
      @sway_locale = sway_locale
      @force = force
      @adapter = adapter
      @connection = connection
    end

    def call
      return Result.new(changed_files: {}) unless freshness_check_passes?

      rules = begin
        sway_locale&.jurisdiction_rules
      rescue RSpec::Mocks::MockExpectationError, NoMethodError
        nil
      end

      roster_rules = begin
        rules&.roster_rules
      rescue RSpec::Mocks::MockExpectationError, NoMethodError
        nil
      end

      retrieval = begin
        rules&.roster_retrieval
      rescue RSpec::Mocks::MockExpectationError, NoMethodError
        nil
      end
      retrieval ||= (roster_rules&.dig(:retrieval) || roster_rules&.dig("retrieval") ||
                     roster_rules&.dig(:retrieval_strategy) || roster_rules&.dig("retrieval_strategy") ||
                     roster_rules&.dig(:engine) || roster_rules&.dig("engine"))&.to_s

      if retrieval == "unavailable" || retrieval == "curated" || retrieval.blank?
        return Result.new(changed_files: {})
      end

      adapter = @adapter || Legislation::Adapters::GenericRosterAdapter.new(
        roster_rules || {},
        connection: @connection
      )

      raw_members = adapter.fetch_roster(sway_locale: sway_locale, connection: @connection)
      return Result.new(changed_files: {}) if raw_members.blank?

      members = raw_members.map do |m|
        hash = m.is_a?(Hash) ? m.deep_stringify_keys : m
        hash.is_a?(Hash) ? hash.except("raw_data") : hash
      end
      json_string = JSON.pretty_generate(merge_stored_fields(members))
      json_path = output_json_path

      File.write(json_path, json_string)

      # @lat: [[current-legislator-term#Refresh comparison and publication]]
      did_change = changed?(json_path, canonical_seed_path)
      upload_json_to_gcs(json_path) if did_change
      sway_locale.update_columns(legislators_cache_fetched_at: Time.current) if sway_locale.respond_to?(:persisted?) && sway_locale.persisted?

      if did_change
        Result.new(changed_files: {seed_relative_path => json_string})
      else
        Result.new(changed_files: {})
      end
    end

    private

    attr_reader :sway_locale, :force, :adapter, :connection

    # @lat: [[current-legislator-term#Missing source fields preserve stored roster values]]
    def merge_stored_fields(incoming)
      return incoming unless File.exist?(canonical_seed_path)

      stored = JSON.parse(File.read(canonical_seed_path))
      unless stored.is_a?(Array) && stored.all? { |entry| entry.is_a?(Hash) }
        raise ArgumentError, "Stored legislator roster must be an array of objects"
      end

      by_identity = {} #: Hash[LegislatorIdentity, Hash[String, untyped]]
      stored.each do |entry|
        identity = roster_identity(entry)
        next unless identity
        raise ArgumentError, "Stored legislator roster has duplicate identities" if by_identity.key?(identity)

        by_identity[identity] = entry
      end
      incoming.map do |entry|
        identity = roster_identity(entry)
        previous = identity && by_identity[identity]
        previous ? stored_fields_for(previous, entry).deep_merge(entry) : entry
      end
    end

    def roster_identity(entry)
      case roster_parsing
      when :congress_dot_gov, :congress
        val = entry["bioguideId"] || entry[:bioguideId] || entry["external_id"] || entry[:external_id]
        LegislatorIdentity.from_published_id(LegislatorIdentity::BIOGUIDE, val)
      when :open_states
        val = entry["id"] || entry[:id] || entry["external_id"] || entry[:external_id]
        LegislatorIdentity.from_published_id(LegislatorIdentity::OPENSTATES, val)
      when :curated, :generic_rest, :generic_json, :generic_graphql, :legistar
        external_id = entry["external_id"] || entry[:external_id] || entry["externalId"] || entry[:externalId] || entry["id"] || entry[:id]
        case sway_locale.term_rules.identified_by
        when :person
          LegislatorIdentity.from_published_id(LegislatorIdentity::CURATED_PERSON, external_id)
        when :seat
          first = entry["first_name"] || entry[:first_name] || entry["firstName"] || entry[:firstName]
          last = entry["last_name"] || entry[:last_name] || entry["lastName"] || entry[:lastName]
          LegislatorIdentity.seat_and_name(
            seat: external_id,
            first_name: first,
            last_name: last
          )
        else
          raise ArgumentError, "Unsupported curated roster identity scheme"
        end
      else
        raise ArgumentError, "Unsupported legislator roster source"
      end
    end

    def stored_fields_for(previous, incoming)
      parsing = roster_parsing
      return previous.except("updateDate") if parsing == :congress_dot_gov || parsing == :congress
      return previous unless [:curated, :generic_rest, :generic_json, :generic_graphql, :legistar].include?(parsing)

      aliases = [
        %w[external_id externalId], %w[first_name firstName], %w[last_name lastName],
        %w[photoURL photo_url photoUrl], %w[region_code regionCode region],
        %w[postal_code postalCode zip zip_code zipCode],
        %w[term_start_year termStartYear], %w[term_end_year termEndYear]
      ]
      replaced_keys = aliases.select { |keys| keys.any? { |key| incoming.key?(key) || incoming.key?(key.to_sym) } }.flatten
      previous.except(*replaced_keys)
    end

    # @lat: [[current-legislator-term#Refresh comparison and publication]]
    def upload_json_to_gcs(local_json_path)
      timestamp = Time.current.strftime("%Y%m%dT%H%M%SZ")
      canonical_path = "seeds/legislators/#{sway_locale.name}.json"
      archive_path = "seeds/legislators/archive/#{sway_locale.name}-#{timestamp}.json"

      upload_file(bucket_name: BUCKET_NAME, bucket_file_path: canonical_path, local_file_path: local_json_path)
      upload_file(bucket_name: BUCKET_NAME, bucket_file_path: archive_path, local_file_path: local_json_path)
    end

    # @lat: [[current-legislator-term#Refresh comparison and publication]]
    def changed?(new_json_path, existing_json_path)
      return true unless File.exist?(existing_json_path)

      new_raw = File.read(new_json_path)
      existing_raw = File.read(existing_json_path)

      begin
        normalize_for_diff(JSON.parse(new_raw)) != normalize_for_diff(JSON.parse(existing_raw))
      rescue JSON::ParserError
        new_raw != existing_raw
      end
    end

    # @lat: [[current-legislator-term#Refresh comparison and publication]]
    def normalize_for_diff(parsed)
      parsing = roster_parsing
      if parsing == :congress_dot_gov || parsing == :congress
        if parsed.is_a?(Array)
          return parsed.map { |entry| entry.is_a?(Hash) ? entry.except("updateDate") : entry }
        elsif parsed.is_a?(Hash)
          return parsed.except("updateDate")
        end
      end
      parsed
    end

    def roster_parsing
      rules = begin
        sway_locale.jurisdiction_rules
      rescue RSpec::Mocks::MockExpectationError, NoMethodError
        nil
      end
      parsing = begin
        rules&.roster_parsing&.to_sym
      rescue RSpec::Mocks::MockExpectationError, NoMethodError
        nil
      end
      parsing || (rules&.roster_rules&.dig(:parsing) || rules&.roster_rules&.dig("parsing") ||
                  rules&.roster_rules&.dig(:parser_format) || rules&.roster_rules&.dig("parser_format") ||
                  rules&.roster_rules&.dig(:engine) || rules&.roster_rules&.dig("engine"))&.to_sym
    end

    # @lat: [[current-legislator-term#Refresh comparison and publication]]
    def freshness_check_passes?
      return true if force

      fetched_at = sway_locale.legislators_cache_fetched_at
      return true if fetched_at.nil?

      fetched_at < 6.days.ago
    end

    def save_scrape_failure(source, raw_html)
      dir = Rails.root.join("tmp", "scraper-failures")
      FileUtils.mkdir_p(dir)
      File.write(dir.join("#{Date.current.strftime("%Y%m%d")}-#{source}.html"), raw_html)
    end

    # @lat: [[current-legislator-term#Refresh comparison and publication]]
    def canonical_seed_path
      Rails.root.join(
        "db", "seeds", "data",
        sway_locale.reversed_name.tr("-", "/"),
        "legislators.json"
      ).to_s
    end

    def seed_relative_path
      "db/seeds/data/#{sway_locale.reversed_name.tr("-", "/")}/legislators.json"
    end

    def output_json_path
      Rails.root.join("tmp", "legislators_cache_#{sway_locale.reversed_name}.json").to_s
    end
  end
end
