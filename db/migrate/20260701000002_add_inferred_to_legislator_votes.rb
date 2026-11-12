# frozen_string_literal: true

# Phase 62 (D-10): marks sponsor-inferred synthetic vote rows (all sponsors
# written as FOR before a real roll-call exists) distinctly from real
# roll-call votes, so the interesting-score defection/close-margin math can
# honestly exclude fabricated data. This migration backfills nothing —
# existing rows initially stay `inferred: false`.
class AddInferredToLegislatorVotes < ActiveRecord::Migration[8.1]
  def change
    add_column :legislator_votes, :inferred, :boolean, null: false, default: false
  end
end
