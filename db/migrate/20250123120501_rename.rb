class Rename < ActiveRecord::Migration[8.0]
  def change
    rename_table :organizations, :bill_organizations
  end
end
