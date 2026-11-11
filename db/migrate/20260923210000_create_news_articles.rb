# frozen_string_literal: true

class CreateNewsArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :news_articles do |t|
      t.string :canonical_url, null: false
      t.string :title, null: false
      t.string :outlet_name, null: false
      t.string :author_name
      t.datetime :published_at
      t.string :article_kind, default: "unknown", null: false

      t.timestamps
    end

    add_index :news_articles, :canonical_url, unique: true
    add_index :news_articles, :outlet_name
    add_index :news_articles, :published_at
  end
end
