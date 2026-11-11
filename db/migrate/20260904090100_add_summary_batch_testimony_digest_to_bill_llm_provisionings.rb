# frozen_string_literal: true

class AddSummaryBatchTestimonyDigestToBillLlmProvisionings < ActiveRecord::Migration[8.1]
  def change
    add_column :bill_llm_provisionings, :summary_batch_testimony_digest, :string
  end
end
