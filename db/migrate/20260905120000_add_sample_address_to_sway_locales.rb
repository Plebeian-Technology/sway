# frozen_string_literal: true

# @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
class AddSampleAddressToSwayLocales < ActiveRecord::Migration[8.1]
  def change
    add_column :sway_locales, :sample_street, :string
    add_column :sway_locales, :sample_postal_code, :string
    add_column :sway_locales, :sample_latitude, :float
    add_column :sway_locales, :sample_longitude, :float
  end
end
