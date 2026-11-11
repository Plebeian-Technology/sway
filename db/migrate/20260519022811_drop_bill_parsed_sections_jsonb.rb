# frozen_string_literal: true

# @lat: [[migrations-name-no-model#Migrations name no model#A column nothing writes is dropped in its own change]]
class DropBillParsedSectionsJsonb < ActiveRecord::Migration[8.1]
  def up
    remove_column :bills, :parsed_sections if column_exists?(:bills, :parsed_sections)
    remove_column :bills, :previous_parsed_sections if column_exists?(:bills, :previous_parsed_sections)
  end

  def down
    add_column :bills, :parsed_sections, :json unless column_exists?(:bills, :parsed_sections)
    add_column :bills, :previous_parsed_sections, :json unless column_exists?(:bills, :previous_parsed_sections)
  end
end
