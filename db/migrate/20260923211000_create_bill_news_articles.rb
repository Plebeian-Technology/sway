# frozen_string_literal: true

class CreateBillNewsArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :bill_news_articles do |t|
      t.references :bill, null: false, foreign_key: {on_delete: :cascade}
      t.references :news_article, null: false, foreign_key: {on_delete: :restrict}
      t.string :match_kind, default: "direct", null: false
      t.text :match_evidence
      t.boolean :approved, default: false, null: false
      t.references :approved_by, foreign_key: {to_table: :users}
      t.datetime :approved_at
      t.integer :review_version, default: 0, null: false
      t.string :stance
      t.references :stance_by, foreign_key: {to_table: :users}
      t.integer :stance_version, default: 0, null: false

      t.timestamps
    end

    add_index :bill_news_articles, [:bill_id, :news_article_id], unique: true
    add_index :bill_news_articles, [:bill_id, :approved]
  end
end
