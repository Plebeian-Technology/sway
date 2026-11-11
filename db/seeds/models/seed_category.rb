# frozen_string_literal: true

# Seeds the 20 active categories. Safe to run repeatedly.
# @lat: [[seed-category-slug-key#Why the slug is read-only on the record]]
class SeedCategory
  # This 20-category list is locked by the product spec — use it verbatim,
  # do NOT alter.
  CATEGORIES = [
    "Immigration",
    "Police",
    "Health",
    "Housing",
    "Infrastructure",
    "Politics",
    "Civil Rights",
    "Education",
    "Economy",
    "Transportation",
    "Environment",
    "Budget & Taxes",
    "Public Safety",
    "Labor & Employment",
    "Criminal Justice",
    "Elections & Voting",
    "Technology & Privacy",
    "Energy",
    "Veterans & Military",
    "Children & Families"
  ].freeze

  def self.call
    CATEGORIES.each do |name|
      Category.find_or_create_by!(slug: Category.slugify(name)) do |c|
        c.name = name
        c.active = true
      end
    end
  end
end
