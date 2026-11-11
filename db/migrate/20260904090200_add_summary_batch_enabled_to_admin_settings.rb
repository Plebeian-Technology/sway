# frozen_string_literal: true

class AddSummaryBatchEnabledToAdminSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_settings, :summary_batch_enabled, :boolean, null: false, default: false
  end
end
