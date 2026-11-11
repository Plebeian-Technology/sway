# frozen_string_literal: true

# Phase 67 D-08 (add-alongside, 67-03-PLAN.md's assumption-delta block): a
# campaign is a first-class record mirroring Organization, kept as a
# separate table rather than promoting both to one general speaker record —
# this phase is admin-only (D-09) with no reader-facing surface to unify.
#
# A campaign may stay unnamed: "324 people sent this letter" is a whole
# record on its own, so the name-uniqueness index only applies where a name
# is present, the same partial-index pattern already used for
# bill_llm_provisionings.summary_run_id.
#
# NON-GOAL, stated so a later phase does not add it by reflex: a campaign
# can NEVER be followed. The rule is kept by not writing a campaign_follows
# table and not adding a campaign reference to organization_follows — there
# is no follow code to disable, a campaign simply has no path into
# NotifyOrganizationFollowersService.
class CreateCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :campaigns do |t|
      # Nullable on purpose — see the class comment above.
      t.string :name

      t.references :sway_locale, null: false, foreign_key: true, index: true

      # The optional tie D-08 allows to an organization that may have run
      # the campaign. Never required — most campaigns tie to nothing.
      t.references :organization, null: true, foreign_key: true, index: true

      t.string :icon_url

      t.timestamps
    end

    add_index :campaigns,
      %i[sway_locale_id name],
      unique: true,
      where: "name IS NOT NULL",
      name: "index_campaigns_on_locale_and_name"
  end
end
