# frozen_string_literal: true

class AddSummaryBatchColumnsToBillLlmProvisionings < ActiveRecord::Migration[8.1]
  def change
    add_column :bill_llm_provisionings, :summary_batch_id, :string
    add_column :bill_llm_provisionings, :summary_batch_expires_at, :datetime

    add_index :bill_llm_provisionings, :summary_batch_id
  end
end
