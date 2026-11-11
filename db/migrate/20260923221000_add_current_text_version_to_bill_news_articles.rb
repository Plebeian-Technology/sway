# frozen_string_literal: true

class AddCurrentTextVersionToBillNewsArticles < ActiveRecord::Migration[8.1]
  def change
    add_reference :bill_news_articles, :current_text_version,
      foreign_key: {to_table: :news_article_text_versions, on_delete: :restrict},
      index: true
  end
end
