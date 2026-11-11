# frozen_string_literal: true

class AddNormalizedKeyToAddresses < ActiveRecord::Migration[8.1]
  def change
    add_column :addresses, :normalized_key, :string
    add_index :addresses, :normalized_key
  end
end
