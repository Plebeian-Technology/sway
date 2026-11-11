# frozen_string_literal: true

require "json_schemer"

# @lat: [[bill-llm-schema-validation-design#Why the categories schema is separate (bill_categories_schema.rb)]]
BILL_CATEGORIES_SCHEMA_HASH = JSON.parse(
  Rails.root.join("config", "schemas", "bill_categories.json").read
).freeze

BILL_CATEGORIES_SCHEMA = JSONSchemer.schema(BILL_CATEGORIES_SCHEMA_HASH)
