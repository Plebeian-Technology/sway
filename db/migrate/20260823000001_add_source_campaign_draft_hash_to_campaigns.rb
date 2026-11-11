# frozen_string_literal: true

# @lat: [[campaign-position-cards#Approving a campaign out of testimony#The draft's content hash is its whole identity]]
#
# @lat: [[campaign-scope-and-identity#Recording which draft a campaign came from]]
class AddSourceCampaignDraftHashToCampaigns < ActiveRecord::Migration[8.1]
  def change
    # Nullable, and NOT a foreign key: the value is a campaign draft's own
    # content hash (Testimony::ReuseGrouper's SHA-256 group id), which lives in
    # a JSON artifact and has no table behind it. Every campaign approved
    # before this column existed keeps nil, which reads as "unknown draft".
    add_column :campaigns, :source_campaign_draft_hash, :string
  end
end
