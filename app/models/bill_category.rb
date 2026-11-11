# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_categories
# Database name: primary
#
#  id          :integer          not null, primary key
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  bill_id     :integer          not null
#  category_id :integer          not null
#
# Indexes
#
#  index_bill_categories_on_bill_id_and_category_id  (bill_id,category_id) UNIQUE
#  index_bill_categories_on_category_id              (category_id)
#
# Foreign Keys
#
#  bill_id      (bill_id => bills.id)
#  category_id  (category_id => categories.id)
#

class BillCategory < ApplicationRecord
  belongs_to :bill
  belongs_to :category

  # @lat: [[bill-category-assignment-integrity#Why BillCategory validates uniqueness in Ruby, not only in the database]]
  validates :bill_id, uniqueness: {scope: :category_id}
end
