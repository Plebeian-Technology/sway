# frozen_string_literal: true

class SwayLocale
  # @lat: [[jurisdiction-rules#Jurisdiction declarations]]
  class JurisdictionRules
    # @lat: [[jurisdiction-rules#Jurisdiction declarations]]
    class Undeclared < StandardError; end

    # @lat: [[jurisdiction-rules#Jurisdiction declarations#Published legislator votes]]
    attr_reader :publishes_legislator_votes

    attr_reader :chamber_label

    # @lat: [[jurisdiction-rules#Jurisdiction declarations#Source pairing]]
    attr_reader :session_numbering

    # @lat: [[jurisdiction-rules#Jurisdiction declarations#Declared bill chambers]]
    attr_reader :default_bill_chamber

    # @lat: [[jurisdiction-rules#Jurisdiction declarations#Declared bill chambers]]
    attr_reader :bill_chambers

    attr_reader :accepted_matter_types

    attr_reader :final_passage_action_ids

    RULE_DOMAINS = %i[legislation hearings vote roster law testimony].freeze

    attr_reader :legislation_rules, :hearings_rules, :vote_rules, :roster_rules, :law_rules, :testimony_rules

    def initialize(
      publishes_legislator_votes:,
      chamber_label:,
      session_numbering:,
      default_bill_chamber:,
      bill_chambers:,
      accepted_matter_types: nil,
      final_passage_action_ids: nil,
      legislation_rules: nil,
      hearings_rules: nil,
      vote_rules: nil,
      roster_rules: nil,
      law_rules: nil,
      testimony_rules: nil
    )
      # @lat: [[jurisdiction-rules#Jurisdiction declarations#Declared bill chambers]]
      unless bill_chambers.include?(default_bill_chamber)
        raise ArgumentError,
          "default_bill_chamber #{default_bill_chamber.inspect} is not one of this " \
          "jurisdiction's chambers #{bill_chambers.inspect}"
      end

      @publishes_legislator_votes = publishes_legislator_votes
      @chamber_label = chamber_label
      @session_numbering = session_numbering
      @default_bill_chamber = default_bill_chamber
      @bill_chambers = bill_chambers.dup.freeze
      types = accepted_matter_types || legislation_rules&.dig(:accepted_matter_types) || legislation_rules&.dig("accepted_matter_types") || []
      @accepted_matter_types = Array(types).map(&:to_s).freeze
      @final_passage_action_ids = final_passage_action_ids ? Array(final_passage_action_ids).map(&:to_i).freeze : nil
      @legislation_rules = legislation_rules ? deep_freeze_rules(legislation_rules) : nil
      @hearings_rules = hearings_rules ? deep_freeze_rules(hearings_rules) : nil
      @vote_rules = vote_rules ? deep_freeze_rules(vote_rules) : nil
      @roster_rules = roster_rules ? deep_freeze_rules(roster_rules) : nil
      @law_rules = law_rules ? deep_freeze_rules(law_rules) : nil
      @testimony_rules = testimony_rules ? deep_freeze_rules(testimony_rules) : nil
    end

    def legacy_path_fallback?
      legislation_rules&.dig(:legacy_path_fallback) == true || legislation_rules&.dig("legacy_path_fallback") == true
    end

    def testimony_classification_enabled?
      testimony_rules&.dig(:enable_classification) == true || testimony_rules&.dig("enable_classification") == true
    end

    def generic_portal_urls
      urls = legislation_rules&.dig(:generic_portal_urls) || legislation_rules&.dig("generic_portal_urls") || []
      Array(urls).map(&:to_s).freeze
    end

    def evidence_publisher
      roster_rules&.dig(:evidence_publisher)&.to_s.presence
    end

    def evidence_jurisdiction
      roster_rules&.dig(:evidence_jurisdiction)&.to_s.presence
    end

    def evidence_source_url
      roster_rules&.dig(:evidence_source_url)&.to_s.presence
    end

    def enable_historical_fallback?
      vote_rules&.dig(:enable_historical_fallback) == true
    end
    alias_method :enable_historical_fallback, :enable_historical_fallback?

    def vote_timezone
      vote_rules&.dig(:timezone)&.to_s.presence
    end

    # @lat: [[jurisdiction-rules#Explicit retrieval and parsing decoupling]]
    def retrieval_for(domain)
      rules = rule_hash_for(domain)
      return nil unless rules.is_a?(Hash)

      val = rules[:retrieval].presence ||
        rules["retrieval"].presence ||
        rules[:retrieval_strategy].presence ||
        rules["retrieval_strategy"].presence ||
        rules[:engine].presence ||
        rules["engine"].presence

      val&.to_s
    end

    # @lat: [[jurisdiction-rules#Explicit retrieval and parsing decoupling]]
    def parsing_for(domain)
      rules = rule_hash_for(domain)
      return nil unless rules.is_a?(Hash)

      val = rules[:parsing].presence ||
        rules["parsing"].presence ||
        rules[:parser_format].presence ||
        rules["parser_format"].presence ||
        rules[:engine].presence ||
        rules["engine"].presence

      val&.to_s
    end

    alias_method :retrieval, :retrieval_for
    alias_method :parsing, :parsing_for

    def legislation_retrieval
      retrieval_for(:legislation)
    end

    def legislation_parsing
      parsing_for(:legislation)
    end

    def hearings_retrieval
      retrieval_for(:hearings)
    end

    def hearings_parsing
      parsing_for(:hearings)
    end

    def vote_retrieval
      retrieval_for(:vote)
    end

    def vote_parsing
      parsing_for(:vote)
    end

    def roster_retrieval
      retrieval_for(:roster)
    end

    def roster_parsing
      parsing_for(:roster)
    end

    def law_retrieval
      retrieval_for(:law)
    end

    def law_parsing
      parsing_for(:law)
    end

    alias_method :legislation_rules_retrieval, :legislation_retrieval
    alias_method :legislation_rules_parsing, :legislation_parsing
    alias_method :hearings_rules_retrieval, :hearings_retrieval
    alias_method :hearings_rules_parsing, :hearings_parsing
    alias_method :vote_rules_retrieval, :vote_retrieval
    alias_method :vote_rules_parsing, :vote_parsing
    alias_method :roster_rules_retrieval, :roster_retrieval
    alias_method :roster_rules_parsing, :roster_parsing
    alias_method :law_rules_retrieval, :law_retrieval
    alias_method :law_rules_parsing, :law_parsing

    private

    def rule_hash_for(domain)
      case domain.to_s.delete_suffix("_rules").to_sym
      when :legislation
        @legislation_rules
      when :hearings
        @hearings_rules
      when :vote, :votes
        @vote_rules
      when :roster
        @roster_rules
      when :law, :laws
        @law_rules
      when :testimony
        @testimony_rules
      else
        raise ArgumentError, "Unknown rule domain: #{domain.inspect}. Valid domains: #{RULE_DOMAINS.inspect}"
      end
    end

    def deep_freeze_rules(rules)
      to_frozen_ordered_options(rules)
    end

    def to_frozen_ordered_options(value)
      case value
      when Hash
        opts = ActiveSupport::OrderedOptions.new
        value.each do |k, v|
          opts[k.to_sym] = to_frozen_ordered_options(v)
        end
        opts.freeze
      when Array
        value.map { |v| to_frozen_ordered_options(v) }.freeze
      else
        value.freeze
      end
    end
  end
end
