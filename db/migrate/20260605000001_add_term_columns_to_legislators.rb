# frozen_string_literal: true

# Phase 65 (R1): reworked in place — prod has not run past schema_migrations
# 20260603140733, so this undeployed migration is edited rather than
# superseded (RESEARCH "Migration Chain to Edit"). Originally added the
# per-legislator election-cycle year columns and an office-status flag
# directly to `legislators` (a mutable-row, person-and-seat-conflated
# design); Full-B splits seat tenure into a first-class `legislator_terms`
# table (20260605000003) instead, so this migration becomes a single
# additive change.
#
# sway_locale_id is added NULLABLE with no in-migration population — the
# 65-10 data migration populates it as part of converting the 180 duplicate
# (district_id, external_id) groups into legislator_terms rows; the 65-10
# finalize migration adds the FK + NOT NULL + UNIQUE(sway_locale_id,
# external_id) once every row has a value, and drops the now-superseded
# person-level district/office-status/election-cycle-year columns from
# legislators. None of that happens here — this plan only adds the column.
#
# The convening-date math this migration used to encode (per-locale anchor
# year + cycle-length helpers) has been ported to TermWindow
# (app/models/term_window.rb, Task 1) — see RESEARCH "Don't Hand-Roll".
class AddTermColumnsToLegislators < ActiveRecord::Migration[8.1]
  def change
    add_column :legislators, :sway_locale_id, :integer
    add_index :legislators, :sway_locale_id
  end
end
