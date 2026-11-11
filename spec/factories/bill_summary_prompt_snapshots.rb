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
FactoryBot.define do
  factory :bill_summary_prompt_snapshot do
    bill
    built_at { Time.current }
  end
end
