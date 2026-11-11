# frozen_string_literal: true

class SwayLocale
  # @lat: [[locale-extension#Planned declarative contract]]
  class ReadinessPreflight
    class Result
      attr_reader :file_path, :filename, :sway_locale_name, :errors, :warnings, :capabilities
      attr_accessor :roster_bootstrap_present, :roster_bootstrap_path,
        :geography_present, :geography_path, :icon_present, :icon_path

      def initialize(file_path:, filename: nil)
        @file_path = file_path
        @filename = filename || File.basename(file_path)
        @sway_locale_name = nil
        @errors = []
        @warnings = []
        @capabilities = {}
        @roster_bootstrap_present = false
        @roster_bootstrap_path = nil
        @geography_present = false
        @geography_path = nil
        @icon_present = false
        @icon_path = nil
      end

      def set_locale_name(name)
        @sway_locale_name = name
      end

      def ready?
        errors.empty?
      end

      def manual_only?
        capabilities[:roster] == :manual_curation &&
          capabilities[:votes] == :manual &&
          capabilities[:law] == :unavailable
      end

      def summary
        status = ready? ? "READY" : "NOT READY"
        mode = manual_only? ? " (manual-only)" : ""
        "SwayLocale #{sway_locale_name || filename}: #{status}#{mode} - #{errors.size} error(s), #{warnings.size} warning(s)"
      end
    end

    class << self
      def check_all(directory = DocumentReader.default_directory)
        paths = DocumentReader.discover_paths(directory)
        paths.map { |path| check_file(path) }
      end

      def check_file(path)
        result = Result.new(file_path: path)

        doc = load_document(path, result)
        return result if doc.nil?

        result.set_locale_name(doc.name)

        check_registries(doc, result)
        check_term_rules(doc, result)
        check_roster_bootstrap(doc, result)
        check_geography(doc, result)
        check_icon(doc, result)
        check_capabilities(doc, result)

        result
      end

      private

      def load_document(path, result)
        DocumentReader.read(path)
      rescue DocumentReader::ValidationError => e
        result.errors << "SwayLocale configuration error in #{result.filename}: #{e.message}"
        nil
      rescue Psych::SyntaxError => e
        result.errors << "SwayLocale YAML syntax error in #{result.filename}: #{e.message}"
        nil
      rescue => e
        result.errors << "SwayLocale load error in #{result.filename}: #{e.message}"
        nil
      end

      def check_registries(doc, result)
        doc.to_jurisdiction_rules
      rescue => e
        result.errors << "SwayLocale #{doc.name} jurisdiction rules registry error: #{e.message}"
      end

      def check_term_rules(doc, result)
        doc.to_term_rules
      rescue => e
        result.errors << "SwayLocale #{doc.name} term rules registry error: #{e.message}"
      end

      def check_roster_bootstrap(doc, result)
        country_dir = doc.country.parameterize(separator: "_")
        region_dir = doc.region.parameterize(separator: "_")
        city_dir = doc.city.parameterize(separator: "_")

        roster_path = File.join("db", "seeds", "data", country_dir, region_dir, city_dir, "legislators.json")
        full_roster_path = Rails.root.join(roster_path).to_s

        result.roster_bootstrap_path = roster_path
        if File.exist?(full_roster_path)
          result.roster_bootstrap_present = true
        else
          result.roster_bootstrap_present = false
          result.errors << "SwayLocale #{doc.name} missing roster bootstrap file at #{roster_path}"
        end
      end

      def check_geography(doc, result)
        is_municipal = (doc.city != doc.region) && (doc.city != "congress")
        return unless is_municipal

        geo_path = File.join("storage", "geojson", "#{doc.name}.geojson")
        full_geo_path = Rails.root.join(geo_path).to_s

        result.geography_path = geo_path
        if File.exist?(full_geo_path)
          result.geography_present = true
        else
          result.geography_present = false
          result.errors << "SwayLocale #{doc.name} missing required geography polygon at #{geo_path}"
        end
      end

      def check_icon(doc, result)
        icon_path = doc.icon_url
        return if icon_path.blank?
        return if icon_path.start_with?("http://", "https://")

        result.icon_path = icon_path
        full_icon_path = Rails.root.join(icon_path).to_s

        if File.exist?(full_icon_path)
          result.icon_present = true
        else
          result.icon_present = false
          result.warnings << "SwayLocale #{doc.name} icon not found at #{icon_path}"
        end
      end

      def check_capabilities(doc, result)
        source_rules = doc.source_rules
        roster_rules = doc.roster_rules || {}
        vote_rules = doc.vote_rules || {}
        law_rules = doc.law_rules || {}

        roster_retrieval = (roster_rules[:retrieval] || roster_rules["retrieval"] || roster_rules[:retrieval_strategy] || roster_rules["retrieval_strategy"])&.to_s.presence
        roster_parsing = (roster_rules[:parsing] || roster_rules["parsing"] || roster_rules[:parser_format] || roster_rules["parser_format"])&.to_s.presence
        roster_engine = (roster_rules[:engine] || roster_rules["engine"])&.to_s.presence
        roster_indicator = roster_retrieval || roster_engine || roster_parsing

        roster_supported = %w[congress congress_dot_gov open_states generic_rest generic_json generic_graphql]
        if roster_retrieval == "unavailable" || roster_engine == "unavailable" || roster_parsing == "unavailable"
          result.capabilities[:roster] = :manual_curation
          result.capabilities[:roster_detail] = "Automatic roster refresh is unavailable (manual curation)"
        elsif roster_indicator == "curated"
          curated_check = roster_rules[:curated_readiness_check] || roster_rules["curated_readiness_check"]
          if curated_check == true
            result.capabilities[:roster] = :automatic
            result.capabilities[:roster_detail] = "Automatic roster refresh via curated"
          else
            result.capabilities[:roster] = :manual_curation
            result.capabilities[:roster_detail] = "Automatic roster refresh is unavailable (manual curation)"
          end
        elsif roster_supported.include?(roster_indicator) && (roster_parsing.nil? || roster_supported.include?(roster_parsing))
          result.capabilities[:roster] = :automatic
          result.capabilities[:roster_detail] = "Automatic roster refresh via #{roster_indicator}"
        else
          unsupported_val = [roster_retrieval, roster_parsing].compact.find { |v| !roster_supported.include?(v) && v != "curated" } || roster_indicator
          result.capabilities[:roster] = :unsupported
          result.errors << "SwayLocale #{doc.name} declared unsupported roster engine: #{unsupported_val.inspect}"
        end

        vote_retrieval = (vote_rules[:retrieval] || vote_rules["retrieval"] || vote_rules[:retrieval_strategy] || vote_rules["retrieval_strategy"])&.to_s.presence
        vote_parsing = (vote_rules[:parsing] || vote_rules["parsing"] || vote_rules[:parser_format] || vote_rules["parser_format"])&.to_s.presence
        vote_engine = (vote_rules[:engine] || vote_rules["engine"])&.to_s.presence
        vote_indicator = vote_retrieval || vote_engine || vote_parsing
        publishes_votes = source_rules.key?(:publishes_legislator_votes) ? source_rules[:publishes_legislator_votes] : source_rules["publishes_legislator_votes"]

        vote_supported = %w[legistar congress_dot_gov generic_csv generic_rest generic_json maryland_general_assembly mga generic_html]
        if vote_retrieval == "manual" || vote_engine == "manual" || vote_parsing == "manual" ||
            vote_retrieval == "unavailable" || vote_engine == "unavailable" || vote_parsing == "unavailable" ||
            publishes_votes == false
          result.capabilities[:votes] = :manual
          result.capabilities[:votes_detail] = "Legislator votes are manually recorded or unpublished"
        elsif vote_retrieval == "open_states" || vote_engine == "open_states" || vote_parsing == "open_states"
          if doc.region_code == "MD"
            result.capabilities[:votes] = :automatic
            result.capabilities[:votes_detail] = "Automated votes scraper via OpenStates (Maryland)"
          else
            result.capabilities[:votes] = :unsupported
            result.capabilities[:votes_detail] = "OpenStates votes scraper only supports Maryland (MD); unsupported for #{doc.region_code}"
            result.errors << "SwayLocale #{doc.name} unsupported votes capability: OpenStates votes scraper only supports Maryland (MD), not #{doc.region_code}"
          end
        elsif vote_supported.include?(vote_indicator) && (vote_parsing.nil? || vote_supported.include?(vote_parsing))
          result.capabilities[:votes] = :automatic
          result.capabilities[:votes_detail] = "Automated votes scraper via #{vote_indicator}"
        else
          unsupported_val = [vote_retrieval, vote_parsing].compact.find { |v| !vote_supported.include?(v) } || vote_indicator
          result.capabilities[:votes] = :unsupported
          result.errors << "SwayLocale #{doc.name} declared unsupported vote engine: #{unsupported_val.inspect}"
        end

        law_retrieval = (law_rules[:retrieval] || law_rules["retrieval"] || law_rules[:retrieval_strategy] || law_rules["retrieval_strategy"])&.to_s.presence
        law_parsing = (law_rules[:parsing] || law_rules["parsing"] || law_rules[:parser_format] || law_rules["parser_format"])&.to_s.presence
        law_engine = (law_rules[:engine] || law_rules["engine"])&.to_s.presence
        law_indicator = law_retrieval || law_engine || law_parsing

        # @lat: [[legislation-pipeline#The legislation pipeline#Maryland PDF law corpus acquisition#Readiness accepts the configured retrieval and parser]]
        law_retrieval_supported = %w[akoma_ntoso git_repo git_tarball uslm_xml congress_service generic_rest generic_html generic_xml local_raw filesystem configured_pdf_catalog]
        law_parsing_supported = %w[akoma_ntoso uslm_xml generic_rest generic_html generic_xml local_raw filesystem pdf_statute_sections]
        law_supported = (law_retrieval_supported + law_parsing_supported).uniq
        if law_retrieval == "unavailable" || law_engine == "unavailable" || law_parsing == "unavailable"
          result.capabilities[:law] = :unavailable
          result.capabilities[:law_detail] = "Law acquisition is unavailable (manual or external)"
        elsif law_supported.include?(law_indicator) &&
            (law_retrieval.nil? || law_retrieval_supported.include?(law_retrieval)) &&
            (law_parsing.nil? || law_parsing_supported.include?(law_parsing))
          result.capabilities[:law] = :automatic
          result.capabilities[:law_detail] = "Automated law source via #{law_indicator}"
          result.capabilities[:law_retrieval] = law_retrieval
          result.capabilities[:law_parsing] = law_parsing
        else
          unsupported_val = if law_retrieval.present? && !law_retrieval_supported.include?(law_retrieval)
            law_retrieval
          elsif law_parsing.present? && !law_parsing_supported.include?(law_parsing)
            law_parsing
          else
            law_indicator
          end
          result.capabilities[:law] = :unsupported
          result.errors << "SwayLocale #{doc.name} declared unsupported law engine: #{unsupported_val.inspect}"
        end
      end
    end
  end
end
