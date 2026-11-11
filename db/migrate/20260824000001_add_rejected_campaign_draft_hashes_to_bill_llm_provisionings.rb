# frozen_string_literal: true

# @lat: [[campaign-position-cards#Approving a campaign out of testimony#Why a decision is read back onto the card]]
#
# @lat: [[campaign-draft-rejection#The problem: a campaign draft has no row]]
class AddRejectedCampaignDraftHashesToBillLlmProvisionings < ActiveRecord::Migration[8.1]
  def change
    # A JSON array of campaign-draft content hashes, mirroring the
    # draft_org_positions column beside it. Not a foreign key and not a table:
    # a campaign draft is derived from the cleaned-testimony artifact and has
    # no row of its own, so its content hash is the only key that survives a
    # re-run of the clean-testimony stage.
    add_column :bill_llm_provisionings, :rejected_campaign_draft_hashes, :text
  end
end
