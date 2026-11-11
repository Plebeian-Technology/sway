class AddUniqueIndexByExternalIdToBills < ActiveRecord::Migration[7.1]
  def change
    add_index :bills, [:external_id, :sway_locale_id], unique: true
  end
end
