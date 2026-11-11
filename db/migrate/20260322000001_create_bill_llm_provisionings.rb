# frozen_string_literal: true

class CreateBillLlmProvisionings < ActiveRecord::Migration[8.1]
  def change
    create_table :bill_llm_provisionings do |t|
      t.references :bill, null: false, foreign_key: true, index: false

      t.text :llm_summary
      t.text :llm_full_breakdown
      t.text :support_reasoning
      t.text :oppose_reasoning

      t.datetime :hearings_fetched_at
      t.datetime :llm_generated_at
      t.datetime :diff_generated_at

      t.string :llm_provider
      t.string :llm_model

      t.timestamps
    end

    add_index :bill_llm_provisionings, :bill_id, unique: true
    add_index :bill_llm_provisionings, :llm_generated_at
  end
end
