# frozen_string_literal: true

require "json_schemer"

# @lat: [[testimony-classification-prompt-design#Why the prompt is split into two methods]]
# @lat: [[testimony-classification-prompt-versioning#Why the version is computed, not hand-bumped]]
# @lat: [[bill-llm-schema-validation-design#Why the schemas are read once at boot and never frozen]]
TESTIMONY_CLASSIFICATION_SCHEMA_HASH = JSON.parse(
  Rails.root.join("config", "schemas", "testimony_classification.json").read
).freeze

TESTIMONY_CLASSIFICATION_SCHEMA = JSONSchemer.schema(TESTIMONY_CLASSIFICATION_SCHEMA_HASH)
