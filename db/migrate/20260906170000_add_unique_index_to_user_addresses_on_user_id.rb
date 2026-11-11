# frozen_string_literal: true

# @lat: [[identity-and-access#A user holds one address]]
class AddUniqueIndexToUserAddressesOnUserId < ActiveRecord::Migration[8.1]
  INDEX_NAME = "index_user_addresses_on_user_id"

  def up
    execute(
      "DELETE FROM user_addresses WHERE id NOT IN (SELECT MAX(id) FROM user_addresses GROUP BY user_id)"
    )

    remove_index :user_addresses, name: INDEX_NAME if index_name_exists?(:user_addresses, INDEX_NAME)
    add_index :user_addresses, :user_id, unique: true, name: INDEX_NAME
  end

  # The rows #up deletes are not restored.
  def down
    remove_index :user_addresses, name: INDEX_NAME if index_name_exists?(:user_addresses, INDEX_NAME)
    add_index :user_addresses, :user_id, name: INDEX_NAME
  end
end
