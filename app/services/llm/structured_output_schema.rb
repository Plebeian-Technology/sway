# frozen_string_literal: true

module Llm
  # @lat: [[llm-structured-output-schema-stripping#Keywords whose value is a property-name map (SCHEMA_MAP_KEYWORDS)]]
  # @lat: [[llm-structured-output-schema-defects#Why stripping exists at all]]
  module StructuredOutputSchema
    # @lat: [[llm-structured-output-schema-stripping#Keywords stripped everywhere (UNSUPPORTED_KEYWORDS)]]
    UNSUPPORTED_KEYWORDS = %w[
      minLength
      maxLength
      pattern
      minimum
      maximum
      exclusiveMinimum
      exclusiveMaximum
      multipleOf
      minItems
      maxItems
      uniqueItems
    ].freeze

    # @lat: [[llm-structured-output-schema-defects#Why a property named like a keyword must not be deleted]]
    SCHEMA_MAP_KEYWORDS = %w[
      properties
      $defs
      definitions
      patternProperties
      dependentSchemas
      dependentRequired
      dependencies
    ].freeze

    # @lat: [[llm-structured-output-schema-defects#Why DATA_VALUE_KEYWORDS' four keywords hold different shapes]]
    DATA_VALUE_KEYWORDS = %w[
      enum
      const
      default
      examples
    ].freeze

    # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes#Settled schema keyword stripping for OpenAI-shaped requests]]
    CACHE = {
      anthropic: {}.compare_by_identity,
      openai: {}.compare_by_identity
    }.freeze #: Hash[Symbol, Hash[Hash[String, untyped], Hash[String, untyped]]]

    MAX_CACHE_ENTRIES = 64

    MUTEX = Mutex.new

    # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes#Settled schema keyword stripping for OpenAI-shaped requests]]
    def self.for_request(schema, dialect: :anthropic)
      dialect_key = dialect.to_sym
      MUTEX.synchronize do
        dialect_cache = CACHE.fetch(dialect_key) do
          raise ArgumentError, "unsupported schema dialect: #{dialect.inspect} (allowed: :anthropic, :openai)"
        end
        cached = dialect_cache[schema]
        next cached if cached

        # @type var built: Hash[String, untyped]
        built = strip(schema)
        # @lat: [[llm-structured-output-schema-defects#Why the cache is keyed by object identity, not schema contents]]
        dialect_cache.clear if dialect_cache.size >= MAX_CACHE_ENTRIES
        dialect_cache[schema] = built
      end
    end

    # @lat: [[llm-structured-output-schema-defects#Why data values are walked differently]]
    def self.strip(node)
      case node
      when Hash
        node.each_with_object({}) do |(key, value), result|
          next if UNSUPPORTED_KEYWORDS.include?(key)

          result[key] =
            if DATA_VALUE_KEYWORDS.include?(key)
              # @lat: [[llm-structured-output-schema-defects#Why data values are walked differently]]
              value.deep_dup
            elsif SCHEMA_MAP_KEYWORDS.include?(key) && value.is_a?(Hash)
              # @lat: [[llm-structured-output-schema-defects#Why a property named like a keyword must not be deleted]]
              value.transform_values { |subschema| strip(subschema) }
            else
              strip(value)
            end
        end
      when Array
        node.map { |value| strip(value) }
      else
        node
      end
    end
  end
end
