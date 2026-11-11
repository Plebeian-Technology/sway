# frozen_string_literal: true

# Phase 52 Plan 11 Task 4 — SPEC R11.
#
# Drops the bill_artifacts mirror table. The Phase 50-era webhook-populated
# read-side projection of FastAPI's bill_artifacts index is replaced by
# BillCreator::ResourceCachePanelSerializer (Plan 11 Task 1), which
# synthesizes the same UI-SPEC Surface 6 prop shape from PipelineRunBill
# stage_results + BillLlmProvisioning.
#
# The `down` block reverse-engineers the original
# 20260511220111_create_bill_artifact_mirrors.rb migration verbatim
# (including the two partial-unique indexes for the nullable version_id
# column and the supporting [bill_external_id, stale] index).
class DropBillArtifactMirrors < ActiveRecord::Migration[8.1]
  def up
    drop_table :bill_artifact_mirrors
  end

  def down
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
end
