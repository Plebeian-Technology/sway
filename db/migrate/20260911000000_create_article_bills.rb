# frozen_string_literal: true

class CreateArticleBills < ActiveRecord::Migration[8.1]
  def change
    create_table :article_bills do |t|
      t.references :bill, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :partner_slug, null: false
      t.string :article_url, null: false
      t.string :article_title, null: false
      t.datetime :published_at
      t.integer :clicks_count, default: 0, null: false
      t.integer :registrations_count, default: 0, null: false
      t.integer :votes_count, default: 0, null: false
      t.integer :pro_votes_count, default: 0, null: false
      t.integer :con_votes_count, default: 0, null: false

      t.timestamps
    end

    add_index :article_bills, [:bill_id, :article_url], unique: true
    add_index :article_bills, [:partner_slug, :bill_id]
    add_index :article_bills, [:organization_id, :published_at]
  end
end
