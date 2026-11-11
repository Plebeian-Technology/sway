# frozen_string_literal: true

class RenameSwayLocalesStateToRegionName < ActiveRecord::Migration[8.1]
  def change
    rename_column :sway_locales, :state, :region_name
    rename_index :sway_locales, "index_sway_locales_on_city_and_state_and_country", "index_sway_locales_on_city_and_region_name_and_country"
  end
end
