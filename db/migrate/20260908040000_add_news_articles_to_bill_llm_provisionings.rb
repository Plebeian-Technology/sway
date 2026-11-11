# frozen_string_literal: true

# @lat: [[llm-summaries#LLM bill summaries#Output is validated, not trusted#Cited local news reporting and domain-restricted web search#Pre-summarization search and article persistence]]
class AddNewsArticlesToBillLlmProvisionings < ActiveRecord::Migration[8.1]
  class MigrationBillLlmProvisioning < ActiveRecord::Base
    self.table_name = "bill_llm_provisionings"
  end

  def change
    add_column :bill_llm_provisionings, :news_articles, :text
    add_column :bill_llm_provisionings, :news_articles_fetched_at, :datetime
    # rubocop:disable Rails/ThreeStateBooleanColumn
    add_column :bill_llm_provisionings, :news_urls_valid, :boolean
    # rubocop:enable Rails/ThreeStateBooleanColumn
    add_column :bill_llm_provisionings, :invalid_news_urls, :text
  end
end
