# frozen_string_literal: true

class AddOrganizationLinkDecisionToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :organization_link_decision, :string
    add_index :campaigns, :organization_link_decision
  end
end
