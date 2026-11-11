# frozen_string_literal: true

class AddPlaceTypesToAddresses < ActiveRecord::Migration[8.1]
  def change
    add_column :addresses, :place_types, :json, default: [], null: false
  end
end
