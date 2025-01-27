class RemoveLevelFromBill < ActiveRecord::Migration[8.0]
  def change
    remove_column :bills, :level, :string
  end
end
