# frozen_string_literal: true

# @lat: [[bills-category-filter#Bills category filter#The single-subject category column is retired]]
class DefaultBillsCategoryToEmptyString < ActiveRecord::Migration[8.1]
  def change
    change_column_default :bills, :category, from: nil, to: ""
  end
end
