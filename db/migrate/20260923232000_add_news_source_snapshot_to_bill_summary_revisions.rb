# frozen_string_literal: true

class AddNewsSourceSnapshotToBillSummaryRevisions < ActiveRecord::Migration[8.1]
  def change
    add_reference :bill_summary_revisions, :news_source_snapshot,
      foreign_key: {to_table: :news_article_source_snapshots, on_delete: :nullify},
      index: true
  end
end
