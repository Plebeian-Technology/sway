# frozen_string_literal: true

class EncryptAddressCoordinates < ActiveRecord::Migration[8.1]
  def up
    remove_index :addresses, [:latitude, :longitude]
    change_column :addresses, :latitude, :string
    change_column :addresses, :longitude, :string
  end

  def down
    change_column :addresses, :latitude, :float
    change_column :addresses, :longitude, :float
    add_index :addresses, [:latitude, :longitude]
  end
end
