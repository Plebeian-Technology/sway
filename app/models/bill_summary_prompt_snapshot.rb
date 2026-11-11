# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_summary_prompt_snapshots
# Database name: primary
#
#  id                :integer          not null, primary key
#  bill_details_text :text
#  built_at          :datetime         not null
#  citations_text    :text
#  facts             :text
#  llm_model         :string
#  llm_provider      :string
#  news_text         :text
#  source_text       :text
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  bill_id           :integer          not null
#  summary_run_id    :string
#
# Indexes
#
#  index_bill_summary_prompt_snapshots_on_bill_id  (bill_id) UNIQUE
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#
# @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
class BillSummaryPromptSnapshot < ApplicationRecord
  belongs_to :bill

  serialize :facts, coder: JSON

  class << self
    def record!(bill:, snapshot:, built_at:, summary_run_id:, llm_model:, llm_provider:, facts:)
      row = find_or_initialize_by(bill_id: bill.id)
      row.update!(
        built_at: built_at,
        summary_run_id: summary_run_id,
        llm_model: llm_model,
        llm_provider: llm_provider,
        bill_details_text: snapshot.bill_details_text,
        source_text: snapshot.source_text,
        citations_text: snapshot.citations_text,
        news_text: snapshot.news_text,
        facts: facts
      )
      row
    end

    def forget!(bill:)
      where(bill_id: bill.id).delete_all
    end
  end
end
