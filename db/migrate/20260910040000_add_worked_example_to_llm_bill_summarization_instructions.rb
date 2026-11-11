# frozen_string_literal: true

class AddWorkedExampleToLlmBillSummarizationInstructions < ActiveRecord::Migration[8.1]
  def change
    add_column :llm_bill_summarization_instructions, :worked_example, :text
  end
end
