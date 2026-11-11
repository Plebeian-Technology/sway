# frozen_string_literal: true

class CreateLlmBillSummarizationInstructions < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_bill_summarization_instructions do |t|
      t.references :sway_locale, null: false, foreign_key: true, index: { unique: true }
      t.text :legislative_body_makeup
      t.json :news_media_website_urls, default: [], null: false
      t.datetime :last_seeded_at

      t.timestamps
    end
  end
end
