class AddIndexToLatitudeAndLongitudeOnAddress < ActiveRecord::Migration[7.1]
  def change
    add_index :addresses, %i[latitude longitude]
  end
end
