# frozen_string_literal: true

# @lat: [[bill-creator-positions-tab#Why testimony report resources expose raw counts and evidence without confidence scores]]
class TestimonyClaimedAffiliationResource < ApplicationResource
  attribute :position do |letter|
    letter["position"]
  end

  attribute :phrase do |letter|
    letter.dig("source_evidence", "phrase")
  end

  attribute :role do |letter|
    letter.dig("source_evidence", "role")
  end

  attribute :sender do |letter|
    letter.dig("source_evidence", "sender")
  end

  attribute :org_name do |letter|
    letter.dig("source_evidence", "org_name")
  end
end
