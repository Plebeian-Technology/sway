# frozen_string_literal: true

class CreateBillSummaryRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :bill_summary_revisions do |t|
      t.references :bill, null: false, foreign_key: true, index: true
      t.text :summary_markdown, null: false
      t.string :origin, null: false
      t.references :actor, foreign_key: {to_table: :users}, index: true
      t.string :llm_provider
      t.string :llm_model
      t.string :publication_role, null: false
      t.string :review_state, null: false
      t.references :restored_from, index: true
      t.datetime :created_at, null: false
    end

    add_foreign_key :bill_summary_revisions, :bill_summary_revisions, column: :restored_from_id
    add_index :bill_summary_revisions, %i[bill_id created_at]
  end
end
