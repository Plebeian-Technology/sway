# frozen_string_literal: true

class CreateNewsArticleSourceUses < ActiveRecord::Migration[8.1]
  def change
    create_table :news_article_source_uses do |t|
      t.references :news_article_source_snapshot, null: false, foreign_key: {on_delete: :cascade}
      t.references :bill_news_article, null: false, foreign_key: {on_delete: :restrict}
      t.references :text_version, null: false, foreign_key: {to_table: :news_article_text_versions, on_delete: :restrict}
      t.text :claim_text, null: false
      t.text :evidence_excerpt, null: false
      t.string :citation_url, null: false
      t.string :grounding_status, default: "pending", null: false
      t.text :grounding_reason

      t.timestamps
    end

    add_index :news_article_source_uses, :news_article_source_snapshot_id, name: "index_source_uses_on_snapshot_id"
    add_index :news_article_source_uses, :bill_news_article_id, name: "index_source_uses_on_bill_news_article_id"
    add_index :news_article_source_uses, :text_version_id, name: "index_source_uses_on_text_version_id"
    add_index :news_article_source_uses, [:news_article_source_snapshot_id, :grounding_status], name: "index_source_uses_on_snapshot_and_status"
  end
end
