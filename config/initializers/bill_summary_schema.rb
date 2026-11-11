# frozen_string_literal: true

require "json_schemer"

# @lat: [[bill-llm-schema-validation-design#What the summary schema is shared between]]
# @lat: [[bill-llm-schema-validation-design#Why the categories schema is separate (bill_categories_schema.rb)]]
BILL_SUMMARY_SCHEMA_HASH = JSON.parse(
  Rails.root.join("config", "schemas", "bill_summary.json").read
).freeze

BILL_SUMMARY_SCHEMA = JSONSchemer.schema(BILL_SUMMARY_SCHEMA_HASH)
