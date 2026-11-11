# frozen_string_literal: true

# @lat: [[campaign-position-cards#Approving a campaign out of testimony#Why a decision is read back onto the card]]
# @lat: [[campaign-scope-and-identity#Recording which draft a campaign came from]]
class CampaignResource < ApplicationResource
  attributes :id, :name, :support, :summary, :sender_count, :letter_count

  attribute :source_campaign_draft_hash do |campaign|
    campaign.source_campaign_draft_hash
  end

  # @lat: [[campaign-organization-link#Why there are four states and not two]]
  attribute :organization_link_decision do |campaign|
    campaign.organization_link_decision
  end

  attribute :organization_id do |campaign|
    campaign.organization_id
  end

  attribute :organization_name do |campaign|
    campaign.organization&.name
  end
end
