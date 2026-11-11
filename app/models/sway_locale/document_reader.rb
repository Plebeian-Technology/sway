# frozen_string_literal: true

require "yaml"
require "psych"
require "uri"
require "ipaddr"
require "digest"

class SwayLocale
  # @lat: [[locale-extension#Planned declarative contract]]
  class DocumentReader
    class Error < StandardError; end

    class ValidationError < Error
      attr_reader :filename, :field_path

      def initialize(message, filename: nil, field_path: nil)
        @filename = filename
        @field_path = field_path
        detail = [
          (filename ? "in #{filename}" : nil),
          (field_path ? "at #{field_path}" : nil)
        ].compact.join(" ")
        super(detail.empty? ? message : "#{message} (#{detail})")
      end
    end

    class DuplicateKeyError < ValidationError; end
    class DuplicateIdentityError < ValidationError; end
    class FilenameMismatchError < ValidationError; end

    class LegislativeSessionDefinition < Data.define(:name, :start_date, :end_date, :active, :upstream_name)
      def initialize(name:, start_date:, end_date:, active: false, upstream_name: nil)
        upstream_name = upstream_name.presence || name
        super
      end

      def active?
        !!active
      end
    end

    class Document
      attr_reader :data, :filename, :legislative_sessions, :news_sources, :source_config_digest
      alias_method :news_sources_digest, :source_config_digest

      def initialize(data, filename: nil)
        @data = deep_freeze(data.deep_dup)
        @filename = filename
        @source_rules = deep_freeze(@data.fetch("source_rules").transform_keys(&:to_sym)) if @data.key?("source_rules")
        @term_rules = deep_freeze(@data.fetch("term_rules").transform_keys(&:to_sym)) if @data.key?("term_rules")
        @legislative_sessions = Array(@data["legislative_sessions"]).map do |s|
          start_d = s["start_date"].is_a?(Date) ? s["start_date"] : Date.iso8601(s["start_date"].to_s)
          end_d = s["end_date"].is_a?(Date) ? s["end_date"] : Date.iso8601(s["end_date"].to_s)
          LegislativeSessionDefinition.new(
            name: s.fetch("name"),
            start_date: start_d,
            end_date: end_d,
            active: s.fetch("active", false),
            upstream_name: s["upstream_name"]
          )
        end.freeze
        @news_sources = deep_freeze(
          Array(@data["news_sources"]).map do |s|
            {
              "url" => DocumentReader.normalize_news_source_url(s["url"]),
              "path_policy" => s["path_policy"]
            }
          end
        )
        canonical = @news_sources.map do |s|
          {
            "url" => s["url"],
            "path_policy" => s["path_policy"]
          }
        end.sort_by { |s| s["url"] }
        @source_config_digest = Digest::SHA256.hexdigest(canonical.to_json).freeze
        freeze
      end

      def schema_version
        data["schema_version"]
      end

      def city
        data["city"]
      end

      def region
        data["region"]
      end

      def region_code
        data["region_code"]
      end

      def country
        data["country"]
      end

      def name
        data["name"]
      end

      def time_zone
        data["time_zone"]
      end

      def icon_url
        data["icon_url"] || data["icon_path"] || "logo.svg"
      end

      def default?
        data["default"] == true
      end

      def sample_address
        data["sample_address"] || {}
      end

      def sample_street
        sample_address["street"]
      end

      def sample_postal_code
        sample_address["postal_code"]
      end

      def sample_latitude
        sample_address["latitude"]&.to_f
      end

      def sample_longitude
        sample_address["longitude"]&.to_f
      end

      def source_rules
        @source_rules || data.fetch("source_rules")
      end

      def term_rules
        @term_rules || data.fetch("term_rules")
      end

      def locale_wide_district_name
        # @lat: [[representative-resolution#Locale-wide district]]
        data.dig("representative_resolution", "locale_wide_district_name")
      end

      def legislation_rules
        (source_rules[:legislation_rules] || data["legislation_rules"])&.deep_symbolize_keys
      end

      def hearings_rules
        (source_rules[:hearings_rules] || data["hearings_rules"])&.deep_symbolize_keys
      end

      def vote_rules
        (source_rules[:vote_rules] || data["vote_rules"])&.deep_symbolize_keys
      end

      def roster_rules
        (source_rules[:roster_rules] || data["roster_rules"])&.deep_symbolize_keys
      end

      def law_rules
        (source_rules[:law_rules] || data["law_rules"])&.deep_symbolize_keys
      end

      def testimony_rules
        (source_rules[:testimony_rules] || data["testimony_rules"])&.deep_symbolize_keys
      end

      def nominatim_viewbox
        data["nominatim_viewbox"]
      end

      def nominatim_bounded
        data["nominatim_bounded"]
      end

      def nominatim_bounded?
        data["nominatim_bounded"] == true
      end

      def nominatim_country_codes
        data["nominatim_country_codes"]
      end

      def to_h
        {
          schema_version: schema_version,
          city: city,
          region: region,
          region_code: region_code,
          country: country,
          name: name,
          time_zone: time_zone,
          icon_url: icon_url,
          default: default?,
          sample_address: sample_address,
          source_rules: source_rules,
          term_rules: term_rules,
          locale_wide_district_name: locale_wide_district_name,
          legislation_rules: legislation_rules,
          hearings_rules: hearings_rules,
          vote_rules: vote_rules,
          roster_rules: roster_rules,
          law_rules: law_rules,
          testimony_rules: testimony_rules,
          news_sources: news_sources,
          nominatim_viewbox: nominatim_viewbox,
          nominatim_bounded: nominatim_bounded,
          nominatim_country_codes: nominatim_country_codes
        }
      end

      def to_sway_locale_attributes
        {
          city: city,
          region: region,
          region_code: region_code,
          country: country,
          name: name,
          time_zone: time_zone,
          icon_url: icon_url,
          sample_address: sample_address,
          sample_street: sample_street,
          sample_postal_code: sample_postal_code,
          sample_latitude: sample_latitude,
          sample_longitude: sample_longitude
        }
      end

      def to_jurisdiction_rules
        SwayLocale::JurisdictionRules.new(
          publishes_legislator_votes: source_rules.fetch(:publishes_legislator_votes),
          chamber_label: source_rules.fetch(:chamber_label),
          session_numbering: source_rules.fetch(:session_numbering).to_sym,
          default_bill_chamber: source_rules.fetch(:default_bill_chamber),
          bill_chambers: source_rules.fetch(:bill_chambers),
          accepted_matter_types: legislation_rules&.dig(:accepted_matter_types) || source_rules[:accepted_matter_types],
          final_passage_action_ids: source_rules[:final_passage_action_ids],
          legislation_rules: legislation_rules,
          hearings_rules: hearings_rules,
          vote_rules: vote_rules,
          roster_rules: roster_rules,
          law_rules: law_rules,
          testimony_rules: testimony_rules
        )
      end

      def to_term_rules
        convening_data = term_rules.fetch(:convening).transform_keys(&:to_sym)
        convening = case convening_data.fetch(:kind).to_s
        when "fixed_day"
          SwayLocale::FixedDayConvening.new(
            month: convening_data.fetch(:month).to_i,
            day: convening_data.fetch(:day).to_i
          )
        when "nth_weekday"
          SwayLocale::NthWeekdayConvening.new(
            month: convening_data.fetch(:month).to_i,
            weekday: convening_data.fetch(:weekday).to_i,
            ordinal: convening_data.fetch(:ordinal).to_i,
            offset_days: convening_data[:offset_days].to_i
          )
        else
          raise ArgumentError, "Unsupported convening calendar kind: #{convening_data[:kind].inspect}"
        end

        SwayLocale::TermRules.new(
          convening: convening,
          cycle_anchor_year: term_rules.fetch(:cycle_anchor_year).to_i,
          cycle_years: term_rules.fetch(:cycle_years).to_i,
          roster_lists_only_current_legislators: term_rules.fetch(:roster_lists_only_current_legislators),
          publishes_term_history: term_rules.fetch(:publishes_term_history),
          publishes_exact_term_dates: term_rules.fetch(:publishes_exact_term_dates),
          identified_by: term_rules.fetch(:identified_by).to_sym,
          seat_chambers: term_rules.fetch(:seat_chambers, {})
        )
      end

      def sync_legislative_sessions!(sway_locale)
        raise ArgumentError, "sway_locale must be present and persisted" unless sway_locale&.persisted?

        yaml_names = legislative_sessions.map(&:name)

        LegislativeSession.transaction do
          if yaml_names.empty?
            sway_locale.legislative_sessions.destroy_all
          else
            sway_locale.legislative_sessions.where.not(name: yaml_names).destroy_all
          end

          legislative_sessions.map do |session_def|
            record = sway_locale.legislative_sessions.find_or_initialize_by(name: session_def.name)
            record.start_date = session_def.start_date
            record.end_date = session_def.end_date
            record.active = session_def.active?
            record.save!
            record
          end
        end
      end

      def sync_news_sources!(sway_locale)
        raise ArgumentError, "sway_locale must be present and persisted" unless sway_locale&.persisted?

        instruction = sway_locale.llm_bill_summarization_instruction || sway_locale.build_llm_bill_summarization_instruction
        target_urls = news_sources.pluck("url")

        if instruction.new_record? || instruction.news_media_website_urls != target_urls
          instruction.news_media_website_urls = target_urls
          instruction.save!
        end
        instruction
      end

      private

      def deep_freeze(value)
        case value
        when Hash
          value.each_with_object({}) do |(k, v), acc|
            acc[deep_freeze(k)] = deep_freeze(v)
          end.freeze
        when Array
          value.map { |v| deep_freeze(v) }.freeze
        else
          value.freeze
        end
      end
    end

    NOMINATIM_FIELDS = %w[
      nominatim_viewbox
      nominatim_bounded
      nominatim_country_codes
    ].freeze

    RULE_FIELDS = %w[
      legislation_rules
      hearings_rules
      vote_rules
      roster_rules
      law_rules
      testimony_rules
    ].freeze

    TOP_LEVEL_FIELDS = (%w[
      schema_version
      city
      region
      region_code
      country
      name
      time_zone
      icon_url
      icon_path
      default
      sample_address
      source_rules
      term_rules
      representative_resolution
      legislative_sessions
      news_sources
    ] + NOMINATIM_FIELDS + RULE_FIELDS).freeze

    NEWS_SOURCE_FIELDS = %w[
      url
      path_policy
    ].freeze

    VALID_PATH_POLICIES = %w[
      search_hint
      restrict
    ].freeze

    IPV4_PART_PATTERN = /(?:0x[0-9a-f]+|0o[0-7]+|\d+)/i
    IPV4_LITERAL_REGEX = /\A#{IPV4_PART_PATTERN}(?:\.#{IPV4_PART_PATTERN})*\z/i

    PRIVATE_HOST_SUFFIXES = %w[
      .localhost
      .local
      .test
      .example
      .invalid
      .internal
      .lan
      .home.arpa
      .home
      .localdomain
      .corp
    ].freeze

    PRIVATE_EXACT_HOSTS = %w[
      localhost
      home.arpa
      host.docker.internal
      gateway.docker.internal
      host.containers.internal
      home
      localdomain
      lan
      broadcasthost
    ].freeze

    LEGISLATIVE_SESSION_FIELDS = %w[
      name
      start_date
      end_date
      active
      upstream_name
    ].freeze

    SAMPLE_ADDRESS_FIELDS = %w[
      street
      postal_code
      latitude
      longitude
    ].freeze

    SOURCE_RULES_FIELDS = (%w[
      publishes_legislator_votes
      chamber_label
      session_numbering
      default_bill_chamber
      bill_chambers
      accepted_matter_types
      final_passage_action_ids
    ] + RULE_FIELDS).freeze

    INTEGRATION_RULE_FIELDS = %w[
      retrieval
      retrieval_strategy
      parsing
      parser_format
      base_url
      local_path
      jurisdiction
      api_key_secret
      metadata_mapping
      endpoints
      headers
      params
      chamber_patterns
      repo
      branch
      accepted_matter_types
      curated_readiness_check
      legacy_path_fallback
      enable_classification
      generic_portal_urls
      evidence_publisher
      evidence_jurisdiction
      evidence_source_url
      enable_historical_fallback
      timezone
    ].freeze

    TERM_RULES_FIELDS = %w[
      convening
      cycle_anchor_year
      cycle_years
      roster_lists_only_current_legislators
      publishes_term_history
      publishes_exact_term_dates
      identified_by
      seat_chambers
    ].freeze

    CONVENING_FIELDS = %w[
      kind
      month
      day
      weekday
      ordinal
      offset_days
    ].freeze

    VALID_SESSION_NUMBERINGS = %w[congress_ordinal term_years].freeze
    VALID_CALENDAR_KINDS = %w[fixed_day nth_weekday].freeze
    VALID_IDENTIFIED_BY = %w[person seat].freeze

    @cache_mutex = Mutex.new
    @discover_cache = {}

    class << self
      def default_directory
        Rails.root.join("config", "sway_locales")
      end

      def discover_paths(directory = default_directory)
        Dir.glob(File.join(directory, "*.yml")).reject do |path|
          base = File.basename(path)
          base.start_with?("_") || base.end_with?(".example.yml") || base == "locale.example.yml"
        end.sort
      end

      def discover(directory = default_directory)
        paths = discover_paths(directory)
        cache_key = discover_cache_key(directory, paths)
        if cache_key
          dir_key, state_key = cache_key
          cached = @cache_mutex.synchronize do
            entry = @discover_cache[dir_key]
            entry[1] if entry && entry[0] == state_key
          end
          return cached.dup if cached
        end

        names = {}

        docs = paths.map do |path|
          doc = read(path)
          if names.key?(doc.name)
            raise DuplicateIdentityError.new(
              "Duplicate SwayLocale identity '#{doc.name}' found in #{path} (already defined in #{names[doc.name]})",
              filename: File.basename(path),
              field_path: "name"
            )
          end
          names[doc.name] = path
          doc
        end

        if cache_key
          dir_key, state_key = cache_key
          docs.freeze
          @cache_mutex.synchronize do
            @discover_cache.clear if !@discover_cache.key?(dir_key) && @discover_cache.size >= 32
            @discover_cache[dir_key] = [state_key, docs]
          end
          return docs.dup
        end

        docs
      end

      def all(directory = default_directory)
        discover(directory)
      end

      def find(name, directory = default_directory)
        all(directory).find { |doc| doc.name == name }
      end

      def find_by_name(name, directory = default_directory)
        find(name, directory)
      end

      def fetch(name, directory = default_directory)
        find_by_name(name, directory) || raise(
          KeyError, "SwayLocale configuration not found for #{name.inspect}"
        )
      end

      def current_for(name_or_locale, directory = default_directory)
        name = name_or_locale.respond_to?(:name) ? name_or_locale.name : name_or_locale.to_s
        fetch(name, directory)
      end

      def declared_locale_names(directory = default_directory)
        all(directory).map(&:name)
      end

      def read(path)
        filename = File.basename(path)
        content = File.read(path)

        ast = parse_ast(content, filename)
        validate_ast(ast, filename)

        raw_data = load_safe_yaml(content, filename)
        validate_schema(raw_data, filename, path)

        Document.new(raw_data, filename: filename)
      end

      # @lat: [[jurisdiction-rules#Explicit retrieval and parsing decoupling]]
      def normalize_hash(rule)
        return nil if rule.nil?
        return rule unless rule.is_a?(Hash)

        hwia = rule.with_indifferent_access

        engine = hwia[:engine]
        retrieval = hwia[:retrieval].presence || hwia[:retrieval_strategy]
        parsing = hwia[:parsing].presence || hwia[:parser_format]

        retrieval ||= engine
        parsing ||= engine
        engine ||= retrieval

        hwia[:retrieval] = retrieval if retrieval.present?
        hwia[:parsing] = parsing if parsing.present?
        hwia[:engine] = engine if engine.present?

        hwia
      end

      def normalize_news_source_url(url)
        return url unless url.is_a?(String)

        trimmed = url.strip
        return trimmed if trimmed.empty?

        uri = begin
          URI.parse(trimmed)
        rescue URI::InvalidURIError, ArgumentError
          return trimmed
        end

        return trimmed unless uri.is_a?(URI::HTTPS) && uri.host && !uri.host.empty?
        return trimmed unless trimmed.match?(/\Ahttps:\/\//i)

        after_scheme = trimmed.sub(/\Ahttps:\/\//i, "")
        authority = after_scheme.split(%r{[/\\?#]}, 2).first || ""
        remainder = after_scheme.delete_prefix(authority)

        if authority.include?("@")
          userinfo_part, host_port = authority.split("@", 2)
          userinfo = "#{userinfo_part}@"
          host_port ||= ""
        else
          userinfo = ""
          host_port = authority
        end

        m = host_port.match(/\A(\[[^\]]+\]|[^:]+)(?::(\d*))?\z/)
        return trimmed unless m

        host_str = m[1] || ""
        port_str = (m[2].present? && m[2].to_i != 443) ? ":#{m[2]}" : ""
        remainder = "/#{remainder}" if remainder.empty? || remainder.start_with?("?", "#")

        "https://#{userinfo}#{host_str.downcase}#{port_str}#{remainder}"
      end

      private

      def discover_cache_key(directory, paths)
        return nil if method(:read).owner != singleton_class || method(:read).source_location&.first != __FILE__

        entries = paths.map do |path|
          st = File.stat(path)
          [path, st.mtime.to_i, st.mtime.nsec, st.size]
        end
        [directory.to_s, entries]
      rescue SystemCallError
        nil
      end

      def parse_ast(content, filename)
        YAML.send(:parse, content)
      rescue Psych::SyntaxError => e
        raise ValidationError.new("Malformed YAML: #{e.message}", filename: filename)
      end

      def validate_ast(node, filename, path = [])
        return unless node

        if node.tag && unsupported_tag?(node.tag)
          raise ValidationError.new(
            "Unsupported object tag: #{node.tag}",
            filename: filename,
            field_path: path.join(".")
          )
        end

        case node.class.name
        when "Psych::Nodes::Mapping"
          seen = {}
          node.children.each_slice(2) do |key_node, val_node|
            key = key_node.value
            key_path = (path + [key]).join(".")
            if seen.key?(key)
              raise DuplicateKeyError.new(
                "Duplicate mapping key #{key.inspect}",
                filename: filename,
                field_path: key_path
              )
            end
            seen[key] = true
            validate_ast(val_node, filename, path + [key])
          end
        when "Psych::Nodes::Sequence"
          node.children.each_with_index do |child, idx|
            validate_ast(child, filename, path + [idx.to_s])
          end
        when "Psych::Nodes::Document"
          validate_ast(node.root, filename, path)
        end
      end

      def unsupported_tag?(tag)
        return false if tag.empty? || tag == "!"

        allowed_tags = %w[
          tag:yaml.org,2002:map
          tag:yaml.org,2002:seq
          tag:yaml.org,2002:str
          tag:yaml.org,2002:int
          tag:yaml.org,2002:float
          tag:yaml.org,2002:bool
          tag:yaml.org,2002:null
          tag:yaml.org,2002:timestamp
        ]
        !allowed_tags.include?(tag)
      end

      def load_safe_yaml(content, filename)
        YAML.safe_load(content, permitted_classes: [Date, Time], aliases: false)
      rescue Psych::DisallowedClass => e
        raise ValidationError.new("Disallowed class in YAML: #{e.message}", filename: filename)
      rescue Psych::BadAlias => e
        raise ValidationError.new("YAML aliases are not allowed: #{e.message}", filename: filename)
      rescue Psych::SyntaxError => e
        raise ValidationError.new("Malformed YAML: #{e.message}", filename: filename)
      end

      def validate_schema(data, filename, full_path)
        unless data.is_a?(Hash)
          raise ValidationError.new("Top-level YAML document must be a mapping", filename: filename)
        end

        data.each_key do |key|
          unless TOP_LEVEL_FIELDS.include?(key)
            raise ValidationError.new("Unknown schema field #{key.inspect}", filename: filename, field_path: key)
          end
        end

        %w[schema_version city region country name time_zone source_rules term_rules news_sources].each do |req|
          if data[req].nil?
            raise ValidationError.new("Missing required field #{req.inspect}", filename: filename, field_path: req)
          end
        end

        unless data["schema_version"] == 1
          raise ValidationError.new("Unsupported schema_version #{data["schema_version"].inspect}, expected 1", filename: filename, field_path: "schema_version")
        end

        expected_slug = SwayLocale.normalize_attributes(
          city: data["city"],
          region_name: data["region"],
          country: data["country"]
        )
        normalized_name = "#{expected_slug[:city]}-#{expected_slug[:state]}-#{expected_slug[:country]}"

        if data["name"] != normalized_name
          raise ValidationError.new(
            "Declared name #{data["name"].inspect} does not match normalized identity #{normalized_name.inspect}",
            filename: filename,
            field_path: "name"
          )
        end

        expected_basename = File.basename(full_path, ".yml")
        if expected_basename != data["name"]
          raise FilenameMismatchError.new(
            "Filename #{filename.inspect} does not match declared name #{data["name"].inspect}",
            filename: filename,
            field_path: "name"
          )
        end

        validate_sample_address(data["sample_address"], filename) if data.key?("sample_address") && data["sample_address"].present?
        validate_source_rules(data["source_rules"], filename, data)
        validate_term_rules(data["term_rules"], filename)
        validate_representative_resolution(data["representative_resolution"], filename) if data.key?("representative_resolution")
        validate_legislative_sessions(data["legislative_sessions"], filename) if data.key?("legislative_sessions")
        validate_news_sources(data["news_sources"], filename) if data.key?("news_sources")
        validate_nominatim_fields(data, filename)

        RULE_FIELDS.each do |rule_field|
          if data.key?(rule_field) && !data[rule_field].nil?
            validate_integration_rule(data[rule_field], rule_field, filename, rule_field)
          end
        end
      end

      def validate_representative_resolution(config, filename)
        unless config.is_a?(Hash)
          raise ValidationError.new("representative_resolution must be a mapping", filename: filename, field_path: "representative_resolution")
        end

        config.each_key do |key|
          unless key == "locale_wide_district_name"
            raise ValidationError.new("Unknown field #{key.inspect} in representative_resolution", filename: filename, field_path: "representative_resolution.#{key}")
          end
        end

        district_name = config["locale_wide_district_name"]
        return if district_name.nil?
        return if district_name.is_a?(String) && district_name.present?

        raise ValidationError.new(
          "locale_wide_district_name must be a non-empty string",
          filename: filename,
          field_path: "representative_resolution.locale_wide_district_name"
        )
      end

      def validate_nominatim_fields(data, filename)
        if data.key?("nominatim_viewbox") && !data["nominatim_viewbox"].nil?
          val = data["nominatim_viewbox"]
          unless val.is_a?(String) && val.match?(/\A-?\d+(\.\d+)?,-?\d+(\.\d+)?,-?\d+(\.\d+)?,-?\d+(\.\d+)?\z/)
            raise ValidationError.new(
              "nominatim_viewbox must be a comma-separated coordinate string '<min_lon>,<max_lat>,<max_lon>,<min_lat>'",
              filename: filename,
              field_path: "nominatim_viewbox"
            )
          end
        end

        if data.key?("nominatim_bounded") && !data["nominatim_bounded"].nil?
          val = data["nominatim_bounded"]
          unless [true, false].include?(val)
            raise ValidationError.new(
              "nominatim_bounded must be a boolean",
              filename: filename,
              field_path: "nominatim_bounded"
            )
          end
        end

        if data.key?("nominatim_country_codes") && !data["nominatim_country_codes"].nil?
          val = data["nominatim_country_codes"]
          unless val.is_a?(String) && val.strip.present?
            raise ValidationError.new(
              "nominatim_country_codes must be a non-empty string",
              filename: filename,
              field_path: "nominatim_country_codes"
            )
          end
        end
      end

      def validate_sample_address(sample, filename)
        unless sample.is_a?(Hash)
          raise ValidationError.new("sample_address must be a mapping", filename: filename, field_path: "sample_address")
        end

        sample.each_key do |key|
          unless SAMPLE_ADDRESS_FIELDS.include?(key)
            raise ValidationError.new("Unknown field #{key.inspect} in sample_address", filename: filename, field_path: "sample_address.#{key}")
          end
        end
      end

      def validate_source_rules(rules, filename, _top_data = {})
        unless rules.is_a?(Hash)
          raise ValidationError.new("source_rules must be a mapping", filename: filename, field_path: "source_rules")
        end

        rules.each_key do |key|
          unless SOURCE_RULES_FIELDS.include?(key)
            raise ValidationError.new("Unknown field #{key.inspect} in source_rules", filename: filename, field_path: "source_rules.#{key}")
          end
        end

        %w[publishes_legislator_votes chamber_label session_numbering default_bill_chamber bill_chambers].each do |req|
          if rules[req].nil?
            raise ValidationError.new("Missing required field #{req.inspect} in source_rules", filename: filename, field_path: "source_rules.#{req}")
          end
        end

        validate_allowlist(rules["session_numbering"], VALID_SESSION_NUMBERINGS, "source_rules.session_numbering", filename)

        unless rules["bill_chambers"].is_a?(Array) && rules["bill_chambers"].all? { |c| c.is_a?(String) && !c.empty? }
          raise ValidationError.new("bill_chambers must be an array of non-empty strings", filename: filename, field_path: "source_rules.bill_chambers")
        end

        unless rules["bill_chambers"].include?(rules["default_bill_chamber"])
          raise ValidationError.new(
            "default_bill_chamber #{rules["default_bill_chamber"].inspect} must be one of bill_chambers #{rules["bill_chambers"].inspect}",
            filename: filename,
            field_path: "source_rules.default_bill_chamber"
          )
        end

        unless [true, false].include?(rules["publishes_legislator_votes"])
          raise ValidationError.new("publishes_legislator_votes must be a boolean", filename: filename, field_path: "source_rules.publishes_legislator_votes")
        end

        if rules.key?("accepted_matter_types")
          unless rules["accepted_matter_types"].is_a?(Array) && rules["accepted_matter_types"].all? { |c| c.is_a?(String) && !c.empty? }
            raise ValidationError.new("accepted_matter_types must be an array of non-empty strings", filename: filename, field_path: "source_rules.accepted_matter_types")
          end
        end

        if rules.key?("final_passage_action_ids")
          unless rules["final_passage_action_ids"].is_a?(Array) && rules["final_passage_action_ids"].all? { |c| c.is_a?(Integer) && c.positive? }
            raise ValidationError.new("final_passage_action_ids must be an array of positive integers", filename: filename, field_path: "source_rules.final_passage_action_ids")
          end
        end

        RULE_FIELDS.each do |rule_field|
          if rules.key?(rule_field) && !rules[rule_field].nil?
            validate_integration_rule(rules[rule_field], rule_field, filename, "source_rules.#{rule_field}")
          end
        end
      end

      # @lat: [[jurisdiction-rules#Explicit retrieval and parsing decoupling]]
      def validate_integration_rule(rule, rule_name, filename, field_path = "source_rules.#{rule_name}")
        unless rule.is_a?(Hash)
          raise ValidationError.new("#{rule_name} must be a mapping", filename: filename, field_path: field_path)
        end

        rule.each_key do |key|
          unless INTEGRATION_RULE_FIELDS.include?(key.to_s)
            raise ValidationError.new(
              "Unknown field #{key.inspect} in #{rule_name}",
              filename: filename,
              field_path: "#{field_path}.#{key}"
            )
          end
        end

        retrieval_val = rule["retrieval"] || rule[:retrieval]
        has_retrieval_key = rule.key?("retrieval") || rule.key?(:retrieval)

        strat_val = rule["retrieval_strategy"] || rule[:retrieval_strategy]
        has_strat_key = rule.key?("retrieval_strategy") || rule.key?(:retrieval_strategy)

        parsing_val = rule["parsing"] || rule[:parsing]
        has_parsing_key = rule.key?("parsing") || rule.key?(:parsing)

        format_val = rule["parser_format"] || rule[:parser_format]
        has_format_key = rule.key?("parser_format") || rule.key?(:parser_format)

        if has_retrieval_key
          unless retrieval_val.is_a?(String) && retrieval_val.present?
            raise ValidationError.new(
              "#{rule_name}.retrieval must be a non-empty string",
              filename: filename,
              field_path: "#{field_path}.retrieval"
            )
          end
        end

        if has_strat_key
          unless strat_val.is_a?(String) && strat_val.present?
            raise ValidationError.new(
              "#{rule_name}.retrieval_strategy must be a non-empty string",
              filename: filename,
              field_path: "#{field_path}.retrieval_strategy"
            )
          end
        end

        if has_parsing_key
          unless parsing_val.is_a?(String) && parsing_val.present?
            raise ValidationError.new(
              "#{rule_name}.parsing must be a non-empty string",
              filename: filename,
              field_path: "#{field_path}.parsing"
            )
          end
        end

        if has_format_key
          unless format_val.is_a?(String) && format_val.present?
            raise ValidationError.new(
              "#{rule_name}.parser_format must be a non-empty string",
              filename: filename,
              field_path: "#{field_path}.parser_format"
            )
          end
        end

        unless rule_name.to_s == "testimony_rules"
          effective_retrieval = retrieval_val.presence || strat_val.presence
          effective_parsing = parsing_val.presence || format_val.presence

          if effective_retrieval.nil?
            raise ValidationError.new(
              "#{rule_name}.retrieval must be a non-empty string",
              filename: filename,
              field_path: "#{field_path}.retrieval"
            )
          end

          if effective_parsing.nil?
            raise ValidationError.new(
              "#{rule_name}.parsing must be a non-empty string",
              filename: filename,
              field_path: "#{field_path}.parsing"
            )
          end
        end

        if rule.key?("enable_classification") || rule.key?(:enable_classification)
          val = rule["enable_classification"] || rule[:enable_classification]
          unless [true, false].include?(val)
            raise ValidationError.new(
              "#{rule_name}.enable_classification must be a boolean",
              filename: filename,
              field_path: "#{field_path}.enable_classification"
            )
          end
        end

        if rule.key?("generic_portal_urls") || rule.key?(:generic_portal_urls)
          urls = rule["generic_portal_urls"] || rule[:generic_portal_urls]
          unless urls.is_a?(Array) && urls.all? { |u| u.is_a?(String) }
            raise ValidationError.new(
              "#{rule_name}.generic_portal_urls must be an array of strings",
              filename: filename,
              field_path: "#{field_path}.generic_portal_urls"
            )
          end
        end

        %w[evidence_publisher evidence_jurisdiction evidence_source_url].each do |attr|
          if rule.key?(attr) || rule.key?(attr.to_sym)
            val = rule[attr] || rule[attr.to_sym]
            unless val.is_a?(String) && val.present?
              raise ValidationError.new(
                "#{rule_name}.#{attr} must be a non-empty string",
                filename: filename,
                field_path: "#{field_path}.#{attr}"
              )
            end
          end
        end

        if rule.key?("enable_historical_fallback") || rule.key?(:enable_historical_fallback)
          val = rule["enable_historical_fallback"]
          val = rule[:enable_historical_fallback] if val.nil?
          unless [true, false].include?(val)
            raise ValidationError.new(
              "#{rule_name}.enable_historical_fallback must be a boolean",
              filename: filename,
              field_path: "#{field_path}.enable_historical_fallback"
            )
          end
        end

        if rule.key?("timezone") || rule.key?(:timezone)
          val = rule["timezone"] || rule[:timezone]
          unless val.is_a?(String) && val.present?
            raise ValidationError.new(
              "#{rule_name}.timezone must be a non-empty string",
              filename: filename,
              field_path: "#{field_path}.timezone"
            )
          end
        end

        base_url_val = rule["base_url"] || rule[:base_url]
        has_base_url = rule.key?("base_url") || rule.key?(:base_url)
        if has_base_url
          unless base_url_val.is_a?(String) && base_url_val.present?
            raise ValidationError.new(
              "#{rule_name}.base_url must be a non-empty string",
              filename: filename,
              field_path: "#{field_path}.base_url"
            )
          end
        end

        meta_val = rule["metadata_mapping"] || rule[:metadata_mapping]
        has_meta = rule.key?("metadata_mapping") || rule.key?(:metadata_mapping)
        if has_meta && !meta_val.is_a?(Hash)
          raise ValidationError.new(
            "#{rule_name}.metadata_mapping must be a mapping",
            filename: filename,
            field_path: "#{field_path}.metadata_mapping"
          )
        end

        pat_val = rule["chamber_patterns"] || rule[:chamber_patterns]
        has_pat = rule.key?("chamber_patterns") || rule.key?(:chamber_patterns)
        if has_pat && !pat_val.is_a?(Hash)
          raise ValidationError.new(
            "#{rule_name}.chamber_patterns must be a mapping",
            filename: filename,
            field_path: "#{field_path}.chamber_patterns"
          )
        end
      end

      def validate_term_rules(rules, filename)
        unless rules.is_a?(Hash)
          raise ValidationError.new("term_rules must be a mapping", filename: filename, field_path: "term_rules")
        end

        rules.each_key do |key|
          unless TERM_RULES_FIELDS.include?(key)
            raise ValidationError.new("Unknown field #{key.inspect} in term_rules", filename: filename, field_path: "term_rules.#{key}")
          end
        end

        %w[convening cycle_anchor_year cycle_years roster_lists_only_current_legislators publishes_term_history publishes_exact_term_dates identified_by].each do |req|
          if rules[req].nil?
            raise ValidationError.new("Missing required field #{req.inspect} in term_rules", filename: filename, field_path: "term_rules.#{req}")
          end
        end

        validate_allowlist(rules["identified_by"], VALID_IDENTIFIED_BY, "term_rules.identified_by", filename)
        validate_seat_chambers(rules, filename)

        unless rules["cycle_anchor_year"].is_a?(Integer)
          raise ValidationError.new("cycle_anchor_year must be an integer", filename: filename, field_path: "term_rules.cycle_anchor_year")
        end

        unless rules["cycle_years"].is_a?(Integer) && rules["cycle_years"].positive?
          raise ValidationError.new("cycle_years must be a positive integer", filename: filename, field_path: "term_rules.cycle_years")
        end

        [true, false].include?(rules["roster_lists_only_current_legislators"]) ||
          raise(ValidationError.new("roster_lists_only_current_legislators must be a boolean", filename: filename, field_path: "term_rules.roster_lists_only_current_legislators"))

        [true, false].include?(rules["publishes_term_history"]) ||
          raise(ValidationError.new("publishes_term_history must be a boolean", filename: filename, field_path: "term_rules.publishes_term_history"))

        [true, false].include?(rules["publishes_exact_term_dates"]) ||
          raise(ValidationError.new("publishes_exact_term_dates must be a boolean", filename: filename, field_path: "term_rules.publishes_exact_term_dates"))

        validate_convening(rules["convening"], filename)
      end

      def validate_seat_chambers(rules, filename)
        return unless rules.key?("seat_chambers")

        path = "term_rules.seat_chambers"
        mapping = rules["seat_chambers"]
        unless mapping.is_a?(Hash)
          raise ValidationError.new("seat_chambers must be a mapping", filename: filename, field_path: path)
        end
        if mapping.empty?
          raise ValidationError.new("seat_chambers must declare at least one title", filename: filename, field_path: path)
        end

        mapping.each do |title, chamber|
          unless title.is_a?(String) && title.present?
            raise ValidationError.new("seat_chambers titles must be nonblank strings", filename: filename, field_path: path)
          end
          unless chamber.is_a?(String) && chamber.present?
            raise ValidationError.new("seat_chambers chambers must be nonblank strings", filename: filename, field_path: "#{path}.#{title}")
          end
        end
      end

      def validate_convening(convening, filename)
        unless convening.is_a?(Hash)
          raise ValidationError.new("convening must be a mapping", filename: filename, field_path: "term_rules.convening")
        end

        convening.each_key do |key|
          unless CONVENING_FIELDS.include?(key)
            raise ValidationError.new("Unknown field #{key.inspect} in convening", filename: filename, field_path: "term_rules.convening.#{key}")
          end
        end

        validate_allowlist(convening["kind"], VALID_CALENDAR_KINDS, "term_rules.convening.kind", filename)

        case convening["kind"]
        when "fixed_day"
          unless convening["month"].is_a?(Integer) && (1..12).cover?(convening["month"])
            raise ValidationError.new("fixed_day month must be an integer 1..12", filename: filename, field_path: "term_rules.convening.month")
          end
          unless convening["day"].is_a?(Integer) && (1..31).cover?(convening["day"])
            raise ValidationError.new("fixed_day day must be an integer 1..31", filename: filename, field_path: "term_rules.convening.day")
          end
        when "nth_weekday"
          unless convening["month"].is_a?(Integer) && (1..12).cover?(convening["month"])
            raise ValidationError.new("nth_weekday month must be an integer 1..12", filename: filename, field_path: "term_rules.convening.month")
          end
          unless convening["weekday"].is_a?(Integer) && (0..6).cover?(convening["weekday"])
            raise ValidationError.new("nth_weekday weekday must be an integer 0..6", filename: filename, field_path: "term_rules.convening.weekday")
          end
          unless convening["ordinal"].is_a?(Integer) && (1..5).cover?(convening["ordinal"])
            raise ValidationError.new("nth_weekday ordinal must be an integer 1..5", filename: filename, field_path: "term_rules.convening.ordinal")
          end
        end
      end

      def validate_allowlist(val, list, field_path, filename)
        unless list.include?(val.to_s)
          raise ValidationError.new(
            "#{val.inspect} is not permitted. Allowed values: #{list.inspect}",
            filename: filename,
            field_path: field_path
          )
        end
      end

      def validate_legislative_sessions(sessions, filename)
        return if sessions.nil?

        unless sessions.is_a?(Array)
          raise ValidationError.new("legislative_sessions must be an array", filename: filename, field_path: "legislative_sessions")
        end

        if sessions.empty?
          raise ValidationError.new("must have at least one active session", filename: filename, field_path: "legislative_sessions")
        end

        seen_names = {}

        sessions.each_with_index do |session, idx|
          path = "legislative_sessions.#{idx}"

          unless session.is_a?(Hash)
            raise ValidationError.new("legislative_session must be a mapping", filename: filename, field_path: path)
          end

          session.each_key do |key|
            unless LEGISLATIVE_SESSION_FIELDS.include?(key)
              raise ValidationError.new("Unknown field #{key.inspect} in legislative_sessions", filename: filename, field_path: "#{path}.#{key}")
            end
          end

          %w[name start_date end_date].each do |req|
            if session[req].nil?
              raise ValidationError.new("Missing required field #{req.inspect} in legislative_sessions", filename: filename, field_path: "#{path}.#{req}")
            end
          end

          unless session["name"].is_a?(String) && session["name"].strip.present?
            raise ValidationError.new("name must be a non-empty string", filename: filename, field_path: "#{path}.name")
          end

          if session.key?("upstream_name") && (!session["upstream_name"].is_a?(String) || session["upstream_name"].strip.empty?)
            raise ValidationError.new("upstream_name must be a non-empty string", filename: filename, field_path: "#{path}.upstream_name")
          end

          if seen_names.key?(session["name"])
            raise ValidationError.new(
              "Duplicate legislative session name #{session["name"].inspect}",
              filename: filename,
              field_path: "#{path}.name"
            )
          end
          seen_names[session["name"]] = true

          start_date = parse_session_date(session["start_date"], "#{path}.start_date", filename)
          end_date = parse_session_date(session["end_date"], "#{path}.end_date", filename)

          if start_date && end_date && end_date < start_date
            raise ValidationError.new("end_date must be on or after start_date", filename: filename, field_path: "#{path}.end_date")
          end

          if session.key?("active") && ![true, false].include?(session["active"])
            raise ValidationError.new("active must be a boolean", filename: filename, field_path: "#{path}.active")
          end
        end

        active_count = sessions.count { |s| s["active"] == true }
        if active_count.zero?
          raise ValidationError.new("must have at least one active session", filename: filename, field_path: "legislative_sessions")
        end
      end

      def parse_session_date(value, field_path, filename)
        return value if value.is_a?(Date)

        if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
          begin
            return Date.iso8601(value)
          rescue ArgumentError
            nil
          end
        end

        raise ValidationError.new("Expected ISO8601 date (YYYY-MM-DD)", filename: filename, field_path: field_path)
      end

      def validate_news_sources(sources, filename)
        unless sources.is_a?(Array)
          raise ValidationError.new("news_sources must be an array", filename: filename, field_path: "news_sources")
        end

        seen_urls = {}

        sources.each_with_index do |source, idx|
          path = "news_sources.#{idx}"

          unless source.is_a?(Hash)
            raise ValidationError.new("news_source must be a mapping", filename: filename, field_path: path)
          end

          source.each_key do |key|
            unless NEWS_SOURCE_FIELDS.include?(key)
              raise ValidationError.new("Unknown field #{key.inspect} in news_sources", filename: filename, field_path: "#{path}.#{key}")
            end
          end

          %w[url path_policy].each do |req|
            if source[req].nil?
              raise ValidationError.new("Missing required field #{req.inspect} in news_sources", filename: filename, field_path: "#{path}.#{req}")
            end
          end

          validate_allowlist(source["path_policy"], VALID_PATH_POLICIES, "#{path}.path_policy", filename)
          validate_news_source_url(source["url"], filename, "#{path}.url")

          canonical_url = normalize_news_source_url(source["url"])
          if seen_urls.key?(canonical_url)
            raise ValidationError.new("Duplicate news source URL #{source["url"].inspect}", filename: filename, field_path: "#{path}.url")
          end
          seen_urls[canonical_url] = true
        end
      end

      def validate_news_source_url(url, filename, field_path)
        unless url.is_a?(String) && url.strip.present?
          raise ValidationError.new("url must be a non-empty string", filename: filename, field_path: field_path)
        end

        trimmed = url.strip
        uri = begin
          URI.parse(trimmed)
        rescue URI::InvalidURIError, ArgumentError
          raise ValidationError.new("url is not a valid URI", filename: filename, field_path: field_path)
        end

        unless uri.is_a?(URI::HTTPS) && uri.scheme&.downcase == "https"
          raise ValidationError.new("url must use https scheme", filename: filename, field_path: field_path)
        end

        authority = trimmed.sub(%r{\Ahttps://}i, "").split(%r{[/\\?#]}, 2).first || ""
        if authority.include?("@") || uri.user.present? || uri.password.present?
          raise ValidationError.new("url must not contain userinfo or credentials", filename: filename, field_path: field_path)
        end

        if uri.port.present? && uri.port != 443
          raise ValidationError.new("url must not specify a custom port", filename: filename, field_path: field_path)
        end

        raw_host = uri.host.to_s.strip
        if raw_host.empty?
          raise ValidationError.new("url host is invalid", filename: filename, field_path: field_path)
        end

        if ip_address?(raw_host)
          raise ValidationError.new("url must not use an IP literal host", filename: filename, field_path: field_path)
        end

        host = raw_host.downcase
        if PRIVATE_EXACT_HOSTS.include?(host) ||
            host.end_with?(*PRIVATE_HOST_SUFFIXES) ||
            !host.match?(Llm::AllowedDomain::VALID_HOST_REGEX)
          raise ValidationError.new("url must not target a local or private destination", filename: filename, field_path: field_path)
        end

        tld = host.split(".").last
        if tld.nil? || tld.match?(/\A\d+\z/) || tld.match?(/\A0x[0-9a-f]+\z/i)
          raise ValidationError.new("url host has invalid or numeric top-level domain", filename: filename, field_path: field_path)
        end
      end

      def ip_address?(host)
        clean = host.to_s.strip.delete_prefix("[").delete_suffix("]").delete_suffix(".")
        return false if clean.empty?
        return true if clean.match?(IPV4_LITERAL_REGEX)
        return false unless clean.include?(":")

        IPAddr.new(clean)
        true
      rescue IPAddr::InvalidAddressError
        false
      end
    end
  end
end

class SwayLocale
  LegislativeSessionDefinition = DocumentReader::LegislativeSessionDefinition
end
