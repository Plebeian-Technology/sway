# frozen_string_literal: true

class MigrateBillLlmProvisioningsForPhase8 < ActiveRecord::Migration[8.1]
  def change
    remove_column :bill_llm_provisionings, :support_reasoning, :text
    remove_column :bill_llm_provisionings, :oppose_reasoning, :text
    add_column :bill_llm_provisionings, :draft_org_positions, :text
    add_column :bill_llm_provisionings, :diff_content, :text
  end
end
