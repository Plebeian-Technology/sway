# frozen_string_literal: true

class CreateNewsArticleTestimonies < ActiveRecord::Migration[8.1]
  def change
    create_table :news_article_testimonies do |t|
      t.references :bill_news_article, null: false, foreign_key: {on_delete: :cascade}
      t.references :news_article_source_snapshot, null: true, foreign_key: {on_delete: :nullify}, index: false
      t.references :news_article_text_version, null: false, foreign_key: {on_delete: :restrict}, index: false
      t.text :argument_markdown, null: false
      t.text :evidence_excerpt, null: false
      t.string :citation_url, null: false
      t.string :author_name
      t.string :outlet_name, null: false
      t.string :stance, null: false
      t.integer :stance_version, default: 0, null: false
      t.integer :review_version, default: 0, null: false
      t.string :text_digest, null: false
      t.string :publication_state, default: "draft", null: false
      t.datetime :published_at

      t.timestamps
    end

    add_index :news_article_testimonies, [:bill_news_article_id, :publication_state], name: "idx_news_testimonies_on_bna_and_pub_state"
    add_index :news_article_testimonies, :news_article_source_snapshot_id, name: "idx_news_testimonies_on_snapshot_id"
    add_index :news_article_testimonies, :news_article_text_version_id, name: "idx_news_testimonies_on_text_version_id"
  end
end
