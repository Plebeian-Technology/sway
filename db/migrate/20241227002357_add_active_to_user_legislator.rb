class AddActiveToUserLegislator < ActiveRecord::Migration[7.2]
  def change
    add_column :user_legislators, :active, :boolean, null: false, default: true
  end
end
