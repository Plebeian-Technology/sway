# frozen_string_literal: true

# == Schema Information
#
# Table name: categories
# Database name: primary
#
#  id         :integer          not null, primary key
#  active     :boolean          default(TRUE), not null
#  name       :string           not null
#  slug       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_categories_on_active  (active)
#  index_categories_on_name    (name) UNIQUE
#  index_categories_on_slug    (slug) UNIQUE
#
FactoryBot.define do
  factory :category do
    sequence(:name) { |n| "Category #{n}" }
    slug { Category.slugify(name) }
    active { true }
  end

  factory :bill_category do
    bill
    category
  end
end
