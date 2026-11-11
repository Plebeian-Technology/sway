# frozen_string_literal: true

# @lat: [[campaign-organization-link#How candidates are proposed, and why the evidence travels with them]]
class CampaignOrganizationCandidateResource < ApplicationResource
  attributes :organization_id, :organization_name, :evidence_kind

  attribute :letter_count do |candidate|
    candidate.letter_count
  end

  attribute :claimed_name do |candidate|
    candidate.claimed_name
  end
end
