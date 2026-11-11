# frozen_string_literal: true

class CreateNewsArticleDiscoveryRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :news_article_discovery_requests do |t|
      t.references :bill, null: false, foreign_key: {on_delete: :cascade}
      t.references :requested_by, null: false, foreign_key: {to_table: :users, on_delete: :restrict}
      t.string :status, null: false, default: "queued"
      t.string :source_config_digest, null: false
      t.string :provider, null: false
      t.string :model, null: false
      t.text :query
      t.json :match_counts, null: false, default: {}
      t.json :diagnostics, null: false, default: []
      t.datetime :completed_at

      t.timestamps
    end

    add_index :news_article_discovery_requests, [:bill_id, :created_at]
    add_index :news_article_discovery_requests, [:bill_id, :status]
    add_index :news_article_discovery_requests, :status
  end
end
