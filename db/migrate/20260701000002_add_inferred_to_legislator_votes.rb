# frozen_string_literal: true

# Phase 62 (D-10): marks sponsor-inferred synthetic vote rows (all sponsors
# written as FOR before a real roll-call exists) distinctly from real
# roll-call votes, so the interesting-score defection/close-margin math can
# honestly exclude fabricated data. This migration backfills nothing —
# existing rows initially stay `inferred: false`. The pre-Phase-62 synthetic
# corpus is retagged by the one-off boot-enqueued
# RetagInferredLegislatorVotesJob (Phase 62 review WR-03), keyed on
# signatures that provably cannot be real data; the daily sweep could NOT
# self-heal this because the CR-02 upsert guard treats a historical
# inferred: false row as real and blocks the re-stamp.
class AddInferredToLegislatorVotes < ActiveRecord::Migration[8.1]
  def change
    add_column :legislator_votes, :inferred, :boolean, null: false, default: false
  end
end
