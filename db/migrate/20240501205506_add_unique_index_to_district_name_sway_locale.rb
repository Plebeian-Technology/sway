class AddUniqueIndexToDistrictNameSwayLocale < ActiveRecord::Migration[7.1]
  def change
    add_index :districts, %i[name sway_locale_id], unique: true
  end
end
