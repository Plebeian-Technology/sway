# frozen_string_literal: true

# @lat: [[bill-category-assigner-design#How renaming a category works alongside assignment — a settled decision]]
class BillCategoryAssigner
  def initialize(bill, raw_names, active_categories)
    @bill = bill
    @raw_names = raw_names
    @active_categories = active_categories
  end

  # @lat: [[bill-category-assigner-design#call: how the 3-category cap works, and why it needs a row lock]]
  def call
    matched = resolve_matches
    if matched.empty?
      raise Llm::SchemaError, "no valid active categories in LLM response (got: #{@raw_names.inspect})"
    end

    # @lat: [[bill-category-assigner-design#call: how the 3-category cap works, and why it needs a row lock]]
    persisted = []
    @bill.with_lock do
      matched.take_while do |cat|
        # @lat: [[bill-category-assigner-design#call: how the 3-category cap works, and why it needs a row lock#Why only active categories count toward the cap]]
        next false if BillCategory.where(bill_id: @bill.id)
          .joins(:category).where(categories: {active: true}).count >= Category::MAX_ACTIVE_PER_BILL
        bc = BillCategory.find_or_create_by!(bill: @bill, category: cat)
        # @lat: [[bill-category-assigner-design#call: how the 3-category cap works, and why it needs a row lock]]
        persisted << cat if bc.previously_new_record?
        true
      end
    end
    persisted
  end

  private

  def resolve_matches
    # @lat: [[bill-category-assigner-design#How renaming a category works alongside assignment — a settled decision]]
    active_by_name = @active_categories.index_by { |c| Category.slugify(c.name) }
    # @lat: [[bill-category-assigner-design#call: how the 3-category cap works, and why it needs a row lock]]
    @raw_names.filter_map { |raw_name|
      active_by_name[Category.slugify(raw_name)]
    }.uniq.first(Category::MAX_ACTIVE_PER_BILL)
  end
end
