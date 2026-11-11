# frozen_string_literal: true

class AddArchivedAtToBills < ActiveRecord::Migration[8.1]
  def change
    add_column :bills, :archived_at, :datetime
    add_index :bills, [:sway_locale_id, :archived_at]
  end
end
