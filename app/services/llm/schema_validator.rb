# frozen_string_literal: true

require "json"

module Llm
  # @lat: [[llm-schema-validator-design#Why the schema-validation failure message is tagged with the provider too]]
  module SchemaValidator
    module_function

    # @lat: [[llm-schema-validator-design#Why the normalizer and checker cannot disagree]]
    def parse_and_validate(text, provider_label:, schema:)
      parsed =
        begin
          JSON.parse(text)
        rescue JSON::ParserError => e
          raise Llm::SchemaError, "Malformed JSON from #{provider_label}: #{e.message.to_s[0, 200]}"
        end

      # @lat: [[llm-schema-validator-design#Why the normalizer and checker cannot disagree]]
      parsed = Llm::ResponseNormalizer.call(parsed, schema.value)

      errors = schema.validate(parsed).to_a
      unless errors.empty?
        pointers = errors.map { |err| err["data_pointer"].to_s }.reject(&:empty?).join(", ")
        detail = pointers.empty? ? errors.first["error"].to_s : pointers
        # @lat: [[llm-schema-validator-design#Why the schema-validation failure message is tagged with the provider too]]
        raise Llm::SchemaError, "Schema validation failed from #{provider_label}: #{detail}"
      end

      parsed
    end
  end
end
