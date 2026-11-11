# frozen_string_literal: true

# Scopes a campaign to one bill and folds campaign_bill_positions into it.
#
# Dropped and rebuilt rather than altered: both tables exist only on this phase
# branch, so there is no production row to preserve, and any dev row predates
# the bill column with nothing to backfill it from.
#
# @lat: [[campaign-scope-and-identity#What the bill prop carries about campaigns]]
class ScopeCampaignsToOneBill < ActiveRecord::Migration[8.1]
  def up
    drop_table :campaign_bill_positions
    drop_table :campaigns

    create_table :campaigns do |t|
      t.references :bill, null: false, foreign_key: true, index: true

      # Still nullable: "324 people sent this letter" is a whole record with
      # no name (D-08), so the uniqueness below applies only where one is
      # present.
      t.string :name

      # @lat: [[campaign-position-cards#Approving a campaign out of testimony#Why a decision is read back onto the card]]
      t.references :organization, null: true, foreign_key: true, index: true

      t.string :icon_url

      # Formerly campaign_bill_positions. summary stays not-null for the
      # reason that table gave: a blank summary is a refusal
      # ApproveCampaignPositionService states, not a five-hundred raised deep
      # inside a save.
      t.string :support, null: false
      t.text :summary, null: false
      t.text :ai_summary
      t.boolean :active, default: false, null: false

      # The sender and letter counts an operator saw before approving — what
      # justified treating this as one campaign.
      t.integer :sender_count
      t.integer :letter_count

      t.timestamps
    end

    # Partial, so any number of unnamed campaigns can sit on one bill. The
    # bill_id index above is kept separately because this one is partial and
    # cannot serve a lookup by bill alone.
    add_index :campaigns,
      %i[bill_id name],
      unique: true,
      where: "name IS NOT NULL",
      name: "index_campaigns_on_bill_and_name"
  end

  # Schema-reversible, not data-reversible: the rows dropped above are gone.
  def down
    drop_table :campaigns

    create_table :campaigns do |t|
      t.string :name
      t.references :sway_locale, null: false, foreign_key: true, index: true
      t.references :organization, null: true, foreign_key: true, index: true
      t.string :icon_url
      t.timestamps
    end

    add_index :campaigns,
      %i[sway_locale_id name],
      unique: true,
      where: "name IS NOT NULL",
      name: "index_campaigns_on_locale_and_name"

    create_table :campaign_bill_positions do |t|
      t.references :campaign, null: false, foreign_key: true, index: true
      t.references :bill, null: false, foreign_key: true, index: false
      t.string :support, null: false
      t.text :summary, null: false
      t.text :ai_summary
      t.boolean :active, default: false, null: false
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
