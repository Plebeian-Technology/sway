# frozen_string_literal: true

# @lat: [[campaign-draft-rejection#Releasing drafts to individual letters]]
class AddIndividualCampaignDraftHashesToBillLlmProvisionings < ActiveRecord::Migration[8.1]
  def change
    add_column :bill_llm_provisionings, :individual_campaign_draft_hashes, :text
  end
end
