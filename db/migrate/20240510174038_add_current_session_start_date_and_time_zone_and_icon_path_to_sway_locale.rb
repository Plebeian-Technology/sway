class AddCurrentSessionStartDateAndTimeZoneAndIconPathToSwayLocale < ActiveRecord::Migration[7.1]
  def change
    add_column :sway_locales, :current_session_start_date, :date
    add_column :sway_locales, :time_zone, :string
    add_column :sway_locales, :icon_path, :string
  end
end
