# frozen_string_literal: true

require "json_schemer"

# @lat: [[bill-llm-schema-validation-design#Why the schemas are read once at boot and never frozen]]
# @lat: [[testimony-stance-classification#Schema constants and validators]]
TESTIMONY_STANCE_CLASSIFICATION_SCHEMA_HASH = JSON.parse(
  Rails.root.join("config", "schemas", "testimony_stance_classification.json").read
).freeze

TESTIMONY_STANCE_CLASSIFICATION_SCHEMA = JSONSchemer.schema(TESTIMONY_STANCE_CLASSIFICATION_SCHEMA_HASH)
