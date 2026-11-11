# frozen_string_literal: true

class AddSummaryBatchChunkSizeToAdminSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_settings, :summary_batch_chunk_size, :integer, null: false, default: 25
  end
end
