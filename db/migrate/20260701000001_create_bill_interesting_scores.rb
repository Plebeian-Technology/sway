# frozen_string_literal: true

# Phase 62 (D-01): append-only history table for the interesting-bill score
# engine. One row is INSERTED per recompute — rows are NEVER updated or
# overwritten, so the table doubles as an audit trail of how a bill's score
# changed over time (D-02). The picker reads the LATEST row per bill via
# `ORDER BY bill_id, id DESC LIMIT 1` (a composite index range scan) rather
# than a separate single-column bill_id index — see 62-RESEARCH.md Question 2.
class CreateBillInterestingScores < ActiveRecord::Migration[8.1]
  def change
    create_table :bill_interesting_scores do |t|
      t.references :bill, null: false, foreign_key: true, index: false
      t.float :raw_score, null: false
      t.float :normalized_score, null: false
      t.text :signals, null: false # JSON breakdown (D-02)
      t.datetime :computed_at, null: false
      t.timestamps
    end
    add_index :bill_interesting_scores, [:bill_id, :id]
  end
end
