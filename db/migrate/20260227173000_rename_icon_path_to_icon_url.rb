# frozen_string_literal: true

class RenameIconPathToIconUrl < ActiveRecord::Migration[8.1]
  def change
    rename_column :organizations, :icon_path, :icon_url
    rename_column :sway_locales, :icon_path, :icon_url
  end
end
