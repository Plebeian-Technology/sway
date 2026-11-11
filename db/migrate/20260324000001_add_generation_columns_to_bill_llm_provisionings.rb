# frozen_string_literal: true

class AddGenerationColumnsToBillLlmProvisionings < ActiveRecord::Migration[8.1]
  def change
    add_column :bill_llm_provisionings, :generation_status, :string
    add_column :bill_llm_provisionings, :generation_error, :text
    add_column :bill_llm_provisionings, :supplemental_testimony, :text
  end
end
