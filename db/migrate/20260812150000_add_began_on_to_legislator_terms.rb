# frozen_string_literal: true

# @lat: [[current-legislator-term#Which term a legislator is serving now#A term carries the day it really began]]
class AddBeganOnToLegislatorTerms < ActiveRecord::Migration[8.1]
  def change
    add_column :legislator_terms, :began_on, :date, null: true
    add_column :legislator_terms, :began_on_source, :string, null: true
  end
end
