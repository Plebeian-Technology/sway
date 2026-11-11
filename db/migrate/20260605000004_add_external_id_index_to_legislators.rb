# frozen_string_literal: true

# @lat: [[migrations-name-no-model#Migrations name no model#A uniqueness validation is not a constraint]]
class AddExternalIdIndexToLegislators < ActiveRecord::Migration[8.1]
  def change
    add_index :legislators, :external_id, name: "index_legislators_on_external_id"
  end
end
