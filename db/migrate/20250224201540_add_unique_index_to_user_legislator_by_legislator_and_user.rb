class AddUniqueIndexToUserLegislatorByLegislatorAndUser < ActiveRecord::Migration[8.0]
  def change
    add_index :user_legislators, [:user_id, :legislator_id], unique: true, name: "by_unique_user_and_legislator"
  end
end
