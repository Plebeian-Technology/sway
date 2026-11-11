# frozen_string_literal: true

# Phase 65 (R3): re-keys the legislator-side score tables to
# legislator_terms instead of legislators, mirroring the additive pattern
# 20260605000001 uses for legislators.sway_locale_id — add the column
# nullable, no in-migration backfill. The 65-10 data migration repoints
# existing legislator_district_scores/legislator_locale_scores rows to the
# right legislator_term, then the 65-10 finalize migration promotes
# legislator_term_id to NOT NULL + unique and drops the now-superseded
# legislator_id column. Keeping both columns present through Waves 2-3 lets
# the app keep booting while models/services migrate to the term key.
#
# 65-06 addendum (R3 freeze): also relaxes legislator_id's NOT NULL +
# UNIQUE(legislator_id) constraint (added by the already-deployed
# 20260602145721 migration) to nullable + non-unique, AND promotes
# legislator_term_id to UNIQUE (pulled forward from 65-10's originally
# planned finalize step — see below for why it can't wait).
#
# legislator_id relaxation: without it, a legislator advancing to a new
# term could never get a SECOND term-keyed score row — the old
# one-row-per-legislator uniqueness would raise RecordNotUnique the
# instant ScoreRecomputeService tried to
# create_or_find_by!(legislator_term: new_term) for a legislator who
# already has a row under a prior term, which is exactly the freeze
# scenario R3 requires a passing spec for. legislator_id itself stays
# populated on write (still the transitional read path) until 65-10 drops
# the column outright.
#
# legislator_term_id UNIQUE: create_or_find_by!(legislator_term:) only
# converges on one row per key when THAT key is DB-uniquely constrained —
# create_or_find_by! optimistically INSERTs and only falls back to a find
# on a caught RecordNotUnique. With legislator_term_id merely indexed
# (not unique) and legislator_id no longer unique either, nothing stops a
# second recompute call for the SAME legislator_term from inserting a
# duplicate row instead of updating the existing one (confirmed via a
# repeat-recompute spec during this plan's execution — two rows landed
# with an identical legislator_term_id). RESEARCH already named
# UNIQUE(legislator_term_id) as the eventual end state; this plan pulls it
# forward from 65-10 because create_or_find_by!'s correctness depends on
# it existing NOW, not after the finalize migration. 65-10 should verify
# this index already exists rather than re-adding it.
#
# Safe to edit this migration in place — its timestamp (20260711000003) is
# after the max deployed schema_migrations version (20260603140733) per
# the phase's deploy-held constraint.
class AddLegislatorTermIdToLegislatorScores < ActiveRecord::Migration[8.1]
  def change
    add_column :legislator_district_scores, :legislator_term_id, :integer
    add_index :legislator_district_scores, :legislator_term_id, unique: true

    add_column :legislator_locale_scores, :legislator_term_id, :integer
    add_index :legislator_locale_scores, :legislator_term_id, unique: true

    change_column_null :legislator_district_scores, :legislator_id, true
    remove_index :legislator_district_scores, :legislator_id
    add_index :legislator_district_scores, :legislator_id

    change_column_null :legislator_locale_scores, :legislator_id, true
    remove_index :legislator_locale_scores, :legislator_id
    add_index :legislator_locale_scores, :legislator_id
  end
end
