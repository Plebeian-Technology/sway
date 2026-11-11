# frozen_string_literal: true

class CreateBillSummaryPromptSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :bill_summary_prompt_snapshots do |t|
      t.references :bill, null: false, foreign_key: true, index: {unique: true}
      t.datetime :built_at, null: false
      t.string :summary_run_id
      t.string :llm_model
      t.string :llm_provider
      t.text :bill_details_text
      t.text :source_text
      t.text :citations_text
      t.text :news_text
      t.text :facts

      t.timestamps
    end
  end
end
