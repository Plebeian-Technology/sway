# frozen_string_literal: true

require "json_schemer"

# @lat: [[news-article-evidence#Grounding decisions]]
NEWS_CLAIM_GROUNDING_SCHEMA_HASH = JSON.parse(
  Rails.root.join("config", "schemas", "news_claim_grounding.json").read
).freeze

NEWS_CLAIM_GROUNDING_SCHEMA = JSONSchemer.schema(NEWS_CLAIM_GROUNDING_SCHEMA_HASH)
