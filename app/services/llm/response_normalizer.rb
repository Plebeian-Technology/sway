# frozen_string_literal: true

module Llm
  # @lat: [[response-normalizer-design#cap_items: quietly changing a response is how earlier bugs went unnoticed — say so]]
  module ResponseNormalizer
    module_function

    # @lat: [[response-normalizer-design#NO_TRIM_FIELDS: why it exists as a name-keyed list, and why it's checked at load]]
    NO_TRIM_FIELDS = %w[cited_section_keys].freeze

    # @lat: [[response-normalizer-design#NO_TRIM_FIELDS: why it exists as a name-keyed list, and why it's checked at load]]
    NO_TRIM_FIELDS.each { |field| BILL_SUMMARY_SCHEMA_HASH.fetch("properties").fetch(field) }

    # @lat: [[response-normalizer-design#cap_items: quietly changing a response is how earlier bugs went unnoticed — say so]]
    def call(value, schema, field_name = nil)
      return value unless schema.is_a?(::Hash)

      case value
      when ::Hash then normalize_object(value, schema)
      when ::Array then normalize_array(value, schema, field_name)
      else value
      end
    end

    def normalize_object(value, schema)
      properties = schema["properties"]
      return value unless properties.is_a?(::Hash)

      value.each_with_object({}) do |(key, subvalue), result|
        result[key] = call(subvalue, properties[key], key)
      end
    end

    def normalize_array(value, schema, field_name = nil)
      capped = cap_items(value, schema, field_name)
      items = schema["items"]
      return capped unless items.is_a?(::Hash)

      capped.map { |element| call(element, items) }
    end

    # @lat: [[response-normalizer-design#cap_items: quietly changing a response is how earlier bugs went unnoticed — say so]]
    def cap_items(value, schema, field_name = nil)
      return dedupe(value, field_name) if NO_TRIM_FIELDS.include?(field_name)

      max_items = schema["maxItems"]
      return value unless max_items.is_a?(::Integer) && value.length > max_items

      SwayLogging.warn(
        "llm.response_normalizer.truncated_array",
        max_items: max_items,
        received: value.length,
        message: "the model returned more items than the schema permits; " \
          "keeping the first #{max_items} rather than discarding the whole response"
      )
      value.first(max_items)
    end

    # @lat: [[response-normalizer-design#dedupe: NO_TRIM_FIELDS' one repair]]
    def dedupe(value, field_name)
      deduped = value.uniq
      return deduped if deduped.length == value.length

      SwayLogging.warn(
        "llm.response_normalizer.deduplicated_array",
        field: field_name,
        received: value.length,
        kept: deduped.length,
        message: "the model repeated an entry in #{field_name}; removed the repeat, kept every distinct entry"
      )
      deduped
    end
  end
end
