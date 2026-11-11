# frozen_string_literal: true

require "json_schemer"

# @lat: [[bill-llm-schema-validation-design#Why bill_positions.json's bounds are tested for drift against bill_summary.json]]
BILL_POSITIONS_SCHEMA_HASH = JSON.parse(
  Rails.root.join("config", "schemas", "bill_positions.json").read
).freeze

BILL_POSITIONS_SCHEMA = JSONSchemer.schema(BILL_POSITIONS_SCHEMA_HASH)
