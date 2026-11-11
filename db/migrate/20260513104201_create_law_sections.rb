# frozen_string_literal: true

# Phase 52 Plan 05 Task 1 — law_sections table (D-45).
#
# Per-locale corpus of Akoma Ntoso law sections. Plan 05 creates the schema +
# AR model; Plan 07's FetchLawService is responsible for upserting rows at
# runtime (DATA dependency satisfied at orchestration time, not build time).
#
# ParseSectionsService resolves citation keys (e.g. "art_1__sec_14") against
# this table, scoped by sway_locale (RESEARCH-REPLAN §Q5 Pitfall 5 — never
# cross-locale).
class CreateLawSections < ActiveRecord::Migration[8.1]
  def change
    create_table :law_sections do |t|
      t.references :sway_locale, null: false, foreign_key: true, index: true
      t.string :key, null: false
      t.string :article, null: false
      t.string :section, null: false
      t.string :title
      t.text :body, null: false
      t.string :source_path, null: false
      t.timestamps
    end
    add_index :law_sections, [:sway_locale_id, :key], unique: true,
      name: "idx_law_sections_on_locale_key"
  end
end
