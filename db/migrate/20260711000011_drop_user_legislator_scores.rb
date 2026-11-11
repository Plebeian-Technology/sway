# frozen_string_literal: true

# Phase 65 (R4): drops the legacy legislator-lifetime aggregate table,
# superseded by term-scoped user_legislator_term_scores (65-02/04). Runs
# strictly AFTER the db/data conversion (20260711000004) has migrated every
# row's counts into a UserLegislatorTermScore.
class DropUserLegislatorScores < ActiveRecord::Migration[8.1]
  def up
    drop_table :user_legislator_scores
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
