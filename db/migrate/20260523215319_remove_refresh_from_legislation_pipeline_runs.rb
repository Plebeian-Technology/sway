# frozen_string_literal: true

# Phase 55 Plan 07 (D-15.2 — CONTRACT half of expand-then-contract):
# Drops the legacy `refresh` boolean column from legislation_pipeline_runs.
# Pitfall 6 mitigation: this migration runs AFTER Plans 03–06 removed every
# source-code read of `refresh`. The expand-half (Plan 03) added
# `download_missing_assets` with a COALESCE(refresh, 1) backfill; Plans 04
# (orchestrator), 05 (preview), 06 (frontend) eliminated remaining reads.
# By the time this migration runs in production, no live worker queries the
# refresh column — SQLite3::SQLException: no such column: refresh cannot
# occur.
#
# Explicit up/down (not change) so the down direction can restore the
# column with a lossy COALESCE backfill for rollback symmetry. The
# original column constraints (`default: true, null: false`) are preserved
# in the down direction for schema parity with the Plan 02
# AddRefreshToLegislationPipelineRuns migration we are inverting.
class RemoveRefreshFromLegislationPipelineRuns < ActiveRecord::Migration[8.1]
  def up
    remove_column :legislation_pipeline_runs, :refresh
  end

  def down
    add_column :legislation_pipeline_runs, :refresh, :boolean,
      null: false, default: true

    # Lossy restore for rollback symmetry: derive refresh from
    # download_missing_assets so historical rows keep a sensible value.
    # COALESCE handles the edge case where download_missing_assets is
    # somehow NULL (it shouldn't be — the column is NOT NULL — but
    # belt-and-suspenders).
    execute(<<~SQL.squish)
      UPDATE legislation_pipeline_runs
      SET refresh = COALESCE(download_missing_assets, 1)
    SQL
  end
end
