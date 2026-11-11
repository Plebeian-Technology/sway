# frozen_string_literal: true

require "json_schemer"

# @lat: [[bill-llm-schema-validation-design#Why the schemas are read once at boot and never frozen]]
SOURCE_KIND_CLASSIFICATION_SCHEMA_HASH = JSON.parse(
  Rails.root.join("config", "schemas", "source_kind_classification.json").read
).freeze

SOURCE_KIND_CLASSIFICATION_SCHEMA = JSONSchemer.schema(SOURCE_KIND_CLASSIFICATION_SCHEMA_HASH)
