# frozen_string_literal: true

class AddGeocodeBackoffToAddresses < ActiveRecord::Migration[8.1]
  def change
    add_column :addresses, :geocode_next_attempt_at, :datetime
    add_column :addresses, :geocode_abandoned_at, :datetime
  end
end
