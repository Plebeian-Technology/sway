# frozen_string_literal: true

# Phase 65 (R1/R4): destructive finalize — runs strictly AFTER the db/data
# conversion (20260711000004), once every legislator row has a populated,
# unique (sway_locale_id, external_id) identity and every legislator-side
# score row has a legislator_term_id. Drops the legacy person-level columns
# legislators.district_id/active/title (district/title/serving are now
# entirely term-derived, per Legislator#active_term/#serving?), promotes
# sway_locale_id to the locale-grained identity key, and promotes both
# legislator-side score tables' legislator_term_id to NOT NULL + drops their
# now-superseded legislator_id column.
#
# UNIQUE(sway_locale_id, external_id) is added ONLY here, never before the
# conversion has run — the defensive duplicate-check raise (ported from
# 20260605000005) lists any residual offender rather than letting the index
# creation fail with an opaque SQLite error.
class FinalizeLegislatorPersonSchema < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationLegislator < ActiveRecord::Base
    self.table_name = "legislators"
  end

  def up
    remove_foreign_key :legislators, :districts
    remove_index :legislators, :district_id
    remove_column :legislators, :district_id
    remove_column :legislators, :active
    remove_column :legislators, :title

    # WR-03 (65-REVIEW): 20260711000004's `next if sway_locale.nil?` branch
    # (an orphaned district_id) deliberately skips backfilling
    # sway_locale_id for that row. Without this pre-flight check, a residual
    # offender would abort the held deploy with a bare SQLite "NOT NULL
    # constraint failed" instead of a diagnostic naming the row(s) —
    # mirroring the defensive-raise pattern used for the duplicate-external-id
    # check immediately below.
    MigrationLegislator.reset_column_information
    orphans = MigrationLegislator.where(sway_locale_id: nil).pluck(:id, :external_id)
    if orphans.any?
      raise <<~MSG.squish
        FinalizeLegislatorPersonSchema: cannot promote sway_locale_id to NOT NULL —
        #{orphans.size} legislator(s) still have a NULL sway_locale_id (orphaned
        district_id, skipped by 20260711000004): #{orphans.inspect}.
        Investigate before re-running.
      MSG
    end

    change_column_null :legislators, :sway_locale_id, false
    add_foreign_key :legislators, :sway_locales

    dupes = MigrationLegislator.group(:sway_locale_id, :external_id).having("COUNT(*) > 1").count
    if dupes.any?
      offenders = dupes.map { |(locale_id, ext_id), cnt|
        "(sway_locale_id=#{locale_id}, external_id=#{ext_id.inspect}, count=#{cnt})"
      }.join(", ")
      raise <<~MSG.squish
        FinalizeLegislatorPersonSchema: cannot add unique index —
        #{dupes.size} duplicate (sway_locale_id, external_id) pair(s) found: #{offenders}.
        The 20260711000004 data migration should have eliminated every duplicate;
        investigate before re-running.
      MSG
    end
    add_index :legislators, [:sway_locale_id, :external_id], unique: true

    change_column_null :legislator_district_scores, :legislator_term_id, false
    remove_foreign_key :legislator_district_scores, :legislators
    remove_index :legislator_district_scores, :legislator_id
    remove_column :legislator_district_scores, :legislator_id

    change_column_null :legislator_locale_scores, :legislator_term_id, false
    remove_foreign_key :legislator_locale_scores, :legislators
    remove_index :legislator_locale_scores, :legislator_id
    remove_column :legislator_locale_scores, :legislator_id
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
