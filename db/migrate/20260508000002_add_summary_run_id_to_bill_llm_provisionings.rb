# frozen_string_literal: true

# Phase 48 D-14 (BL-01 fix): canonical lookup key for the summary_generated
# webhook receiver. Mirrors FastAPI-side summary_run_id (UUID4 stamped when
# Rails enqueues a summary). Webhook arrives keyed by this value first;
# fallback to (bill_external_id + status='pending' + most-recent) covers
# races where the summary completed before Rails persisted the value.
class AddSummaryRunIdToBillLlmProvisionings < ActiveRecord::Migration[8.1]
  def change
    add_column :bill_llm_provisionings, :summary_run_id, :string
    add_index :bill_llm_provisionings, :summary_run_id, unique: true,
      where: "summary_run_id IS NOT NULL",
      name: "index_bill_llm_provisionings_on_summary_run_id"
  end
end
