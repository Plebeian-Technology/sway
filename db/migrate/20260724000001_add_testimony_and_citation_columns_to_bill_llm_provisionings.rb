# frozen_string_literal: true

# Phase 63 Plan 01 (D-06/D-07/D-08/D-10/D-15): lays the persistence
# foundation for testimony extraction (HEAR-02), testimony-only positions
# generation (REAS-01), and citation validation (SUMM-03). All five columns
# are nullable, populated lazily like the existing LLM columns on this table.
class AddTestimonyAndCitationColumnsToBillLlmProvisionings < ActiveRecord::Migration[8.1]
  def change
    add_column :bill_llm_provisionings, :extracted_testimony, :text
    add_column :bill_llm_provisionings, :testimony_fetched_at, :datetime
    add_column :bill_llm_provisionings, :testimony_attachments, :text
    add_column :bill_llm_provisionings, :citations_valid, :boolean
    add_column :bill_llm_provisionings, :invalid_citations, :text
  end
end
