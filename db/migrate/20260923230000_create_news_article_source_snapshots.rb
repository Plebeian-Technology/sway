# frozen_string_literal: true

class CreateNewsArticleSourceSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :news_article_source_snapshots do |t|
      t.references :bill, null: false, foreign_key: {on_delete: :cascade}
      t.string :purpose, null: false
      t.string :run_receipt
      t.references :actor, foreign_key: {to_table: :users, on_delete: :nullify}
      t.json :source_entries, default: [], null: false
      t.string :digest, null: false

      t.timestamps
    end

    add_index :news_article_source_snapshots, [:bill_id, :created_at]
    add_index :news_article_source_snapshots, [:bill_id, :purpose]
    add_index :news_article_source_snapshots, :digest
    add_index :news_article_source_snapshots, :run_receipt
  end
end
