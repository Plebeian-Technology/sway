# frozen_string_literal: true

# @lat: [[migrations-name-no-model#Migrations name no model#A uniqueness validation is not a constraint]]
class AddUniqueIndexToCategoriesName < ActiveRecord::Migration[8.1]
  def change
    add_index :categories, :name, unique: true
  end
end
