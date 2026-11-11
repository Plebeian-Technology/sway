# frozen_string_literal: true

# Phase 50 D-09: Rails-side mirror of FastAPI's bill_artifacts index. Backs the
# resource cache visibility panel on the Bill Creator Pipeline & LLM tab.
# version_id is nullable (some tiers — e.g. summary — are not version-scoped).
#
# @lat: [[sqlite-partial-unique-index-gotchas#Rails 8.1's change can't always infer down for these]]
class CreateBillArtifactMirrors < ActiveRecord::Migration[8.1]
  def up
    create_table :bill_artifact_mirrors do |t|
      t.string   :bill_external_id,   null: false
      t.string   :version_id,         null: true
      t.string   :tier,               null: false
      t.datetime :last_generated_at,  null: false
      t.boolean  :stale,              null: false, default: false
      t.string   :source_artifact_id, null: true
      t.string   :path,               null: true
      t.timestamps
    end

    add_index :bill_artifact_mirrors,
      [:bill_external_id, :tier, :version_id],
      unique: true,
      where: "version_id IS NOT NULL",
      name: "index_bam_bill_tier_version_nn"

    add_index :bill_artifact_mirrors,
      [:bill_external_id, :tier],
      unique: true,
      where: "version_id IS NULL",
      name: "index_bam_bill_tier_no_version"

    add_index :bill_artifact_mirrors,
      [:bill_external_id, :stale],
      name: "index_bam_bill_stale"
  end

  def down
    drop_table :bill_artifact_mirrors
  end
end
