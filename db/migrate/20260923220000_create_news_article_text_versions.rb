# frozen_string_literal: true

class CreateNewsArticleTextVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :news_article_text_versions do |t|
      t.references :news_article, null: false, foreign_key: {on_delete: :restrict}
      t.text :text
      t.string :digest, null: false
      t.string :origin, null: false, default: "retrieved"
      t.string :extraction_status, null: false, default: "extracted"
      t.references :actor, foreign_key: {to_table: :users}
      t.string :requested_url
      t.string :final_url

      t.timestamps
    end

    add_index :news_article_text_versions, [:news_article_id, :created_at]
    add_index :news_article_text_versions, [:news_article_id, :digest]
    add_index :news_article_text_versions, :digest
  end
end
