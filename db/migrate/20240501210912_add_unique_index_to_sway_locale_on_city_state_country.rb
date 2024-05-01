class AddUniqueIndexToSwayLocaleOnCityStateCountry < ActiveRecord::Migration[7.1]
  def change
    add_index :sway_locales, %i[city state country], unique: true
  end
end
