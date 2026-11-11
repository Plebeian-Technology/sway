# frozen_string_literal: true

# PROD-CR-01 stage 3: durable cache of LLM attachment-name verdicts.
#
# Only LLM verdicts are cached. Testimony::NameRules' allow/deny stages are
# pure and free, so caching them would buy nothing and would make a rule edit
# sticky — a corrected denylist pattern would not take effect for any
# attachment already classified. Recomputing the rules every run keeps rule
# changes immediate.
#
# SUPERSEDED by 20260725000002 (A-CR-01): the T-63-08 premise below is false
# against the live recording — Legistar's two attachment collections share one
# id space — so the key is now attachment_id alone. Left verbatim because this
# migration has already run in other development databases.
#
# The key is (source_endpoint, attachment_id), NOT attachment_id alone: per
# T-63-08, a MatterAttachmentId and an EventItemMatterAttachment id occupy
# different Legistar id spaces and can carry the same numeric value. This
# mirrors the attachment file basename for exactly that reason.
class CreateTestimonyAttachmentClassifications < ActiveRecord::Migration[8.1]
  def change
    create_table :testimony_attachment_classifications do |t|
      t.string :source_endpoint, null: false
      t.integer :attachment_id, null: false
      t.string :label, null: false
      t.string :attachment_name
      t.string :model
      t.timestamps
    end

    add_index :testimony_attachment_classifications,
      %i[source_endpoint attachment_id],
      unique: true,
      name: "index_testimony_classifications_on_endpoint_and_attachment"
  end
end
