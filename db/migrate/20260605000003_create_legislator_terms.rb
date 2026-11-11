# frozen_string_literal: true

# Phase 65 (R2): reworked in place — prod had not run past schema_migrations
# 20260603140733, so this undeployed migration was edited rather than
# superseded. Supersedes the phase-59 provisional/finalized
# `legislator_term_snapshots` design entirely.
#
# @lat: [[legislator-term-write-guard-history#Terms are inserted, never mutated in place]]
class CreateLegislatorTerms < ActiveRecord::Migration[8.1]
  def change
    create_table :legislator_terms do |t|
      t.integer :legislator_id, null: false
      t.integer :district_id, null: false
      t.string :title
      t.integer :term_start_year, null: false
      t.integer :term_end_year, null: false

      t.timestamps null: false
    end

    add_index :legislator_terms, [:legislator_id, :term_start_year],
      unique: true, name: "index_legislator_terms_on_legislator_id_and_term_start_year"
    add_index :legislator_terms, :district_id

    add_foreign_key :legislator_terms, :legislators
    add_foreign_key :legislator_terms, :districts
  end
end
