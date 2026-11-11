# frozen_string_literal: true

# Phase 65 (R4): term-scoped mirror of UserLegislatorScore. The existing
# user_legislator_scores table aggregates a user's agreement with a
# UserLegislator relationship for its whole lifetime; this new table keys the
# same four agreement counters to a specific legislator_term instead, so
# agreement history survives a legislator's district change or a new
# election cycle without conflating terms together.
#
# Purely additive — the 65-10 data migration is what populates this table
# from user_legislator_scores and drops the old table; this plan only
# creates the shape.
class CreateUserLegislatorTermScores < ActiveRecord::Migration[8.1]
  def change
    create_table :user_legislator_term_scores do |t|
      t.integer :user_legislator_id, null: false
      t.integer :legislator_term_id, null: false
      t.integer :count_agreed, null: false, default: 0
      t.integer :count_disagreed, null: false, default: 0
      t.integer :count_no_legislator_vote, null: false, default: 0
      t.integer :count_legislator_abstained, null: false, default: 0

      t.timestamps
    end

    add_index :user_legislator_term_scores, [:user_legislator_id, :legislator_term_id],
      unique: true, name: "index_user_legislator_term_scores_on_ul_and_term"
    add_foreign_key :user_legislator_term_scores, :user_legislators
    add_foreign_key :user_legislator_term_scores, :legislator_terms
  end
end
