# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-category-assignment-integrity#Why MAX_ACTIVE_PER_BILL is one constant]]
RSpec.describe "Category::MAX_ACTIVE_PER_BILL (C2-IN-05)" do
  it "is the one name for the cap" do
    expect(Category::MAX_ACTIVE_PER_BILL).to eq(3)
  end

  # Admin::CategoriesController#reactivation_would_exceed_cap? writes its limit
  # into a raw SQL fragment, which no test of behavior can read back out.
  # Checking the SQL it produces is the only way to catch that number drifting.
  it "is the threshold Admin::CategoriesController reactivation guard emits" do
    sql = BillCategory
      .joins(:category)
      .where(categories: {active: true})
      .group(:bill_id)
      .having(Arel.sql("COUNT(*) >= #{Category::MAX_ACTIVE_PER_BILL}"))
      .select(:bill_id)
      .to_sql

    expect(Admin::CategoriesController.new.send(:bills_at_active_cap).to_sql).to eq(sql)
  end

  # The limits in the service and the controller can be seen from the outside, so
  # this checks them where they bite: one over the limit is refused.
  it "is the count at which BillCategoryAssigner stops persisting" do
    bill = create(:bill)
    names = (1..(Category::MAX_ACTIVE_PER_BILL + 2)).map do |i|
      create(:category, name: "Cap Topic #{i}", active: true).name
    end

    # .to_a matches what all three real callers do. The assigner expects an array
    # of Category objects, which #resolve_matches indexes by name, not a query.
    BillCategoryAssigner.new(bill, names, Category.where(active: true).to_a).call

    expect(bill.categories.where(active: true).count).to eq(Category::MAX_ACTIVE_PER_BILL)
  end
end
