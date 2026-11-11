# frozen_string_literal: true

# Phase 67 D-08: mirrors organization_bill_positions. summary stays not-null
# for the same reason that table does — a blank summary is a refusal the
# approval service states (Plan 09's ApproveCampaignPositionService), rather
# than a five-hundred raised deep inside a save.
class CreateCampaignBillPositions < ActiveRecord::Migration[8.1]
  def change
    create_table :campaign_bill_positions do |t|
      t.references :campaign, null: false, foreign_key: true, index: true
      t.references :bill, null: false, foreign_key: true, index: false

      t.string :support, null: false
      t.text :summary, null: false
      t.text :ai_summary
      t.boolean :active, default: false, null: false

      # The sender and letter counts an operator saw before approving —
      # what justified treating this as one campaign.
      t.integer :sender_count
      t.integer :letter_count

      t.timestamps
    end

    add_index :campaign_bill_positions,
      %i[bill_id campaign_id],
      unique: true,
      name: "index_campaign_bill_positions_on_bill_and_campaign"
  end
end
