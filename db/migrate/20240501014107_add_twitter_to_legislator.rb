class AddTwitterToLegislator < ActiveRecord::Migration[7.1]
  def change
    add_column :legislators, :twitter, :string
  end
end
