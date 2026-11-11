class AddScheduledReleaseDateUtcToBill < ActiveRecord::Migration[7.2]
  def change
    add_column :bills, :scheduled_release_date_utc, :date, null: true

    add_index :bills, [:scheduled_release_date_utc, :sway_locale_id], unique: true
  end
end
