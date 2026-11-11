# frozen_string_literal: true

# Phase 55 Plan 03 (D-15.1 — EXPAND half of expand-then-contract):
# Adds a per-run boolean toggle that the orchestrator (Plan 04) reads to decide
# whether to download missing artifacts at the start of each stage. Cuts over
# the `refresh` semantics under a more descriptive name; Plan 07 will drop the
# `refresh` column in the CONTRACT half once all source-code reads of it are
# gone.
#
# Backfill: existing rows inherit COALESCE(refresh, 1) so semantics are
# preserved through the cutover window. Both columns coexist during Plans
# 03–06; no source code reads `refresh` after this plan lands.
#
# Explicit up/down (not change) so the backfill SQL is reversible-by-omission
# on rollback — `def down` simply removes the new column.
class AddDownloadMissingAssetsToLegislationPipelineRuns < ActiveRecord::Migration[8.1]
  def up
    add_column :legislation_pipeline_runs, :download_missing_assets, :boolean,
      null: false, default: true

    execute(<<~SQL.squish)
      UPDATE legislation_pipeline_runs
      SET download_missing_assets = COALESCE(refresh, 1)
    SQL
  end

  def down
    remove_column :legislation_pipeline_runs, :download_missing_assets
  end
end
