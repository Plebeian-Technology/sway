class RemoveAddressFromLegislator < ActiveRecord::Migration[8.0]
  def change
    remove_column :legislators, :address_id, :integer
  end
end
