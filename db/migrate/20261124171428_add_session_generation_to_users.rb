# frozen_string_literal: true

class AddSessionGenerationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :session_generation, :integer, default: 0, null: false
  end
end
