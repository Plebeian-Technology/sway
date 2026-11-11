# frozen_string_literal: true

# @lat: [[query-plan-indexes#Bill of the month reads by locale then date]]
class AddLocaleAndReleaseDateIndexToBills < ActiveRecord::Migration[8.1]
  def change
    add_index :bills,
      [:sway_locale_id, :scheduled_release_date_utc],
      name: "index_bills_on_locale_and_release_date"
  end
end
