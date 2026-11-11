# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe "BillCategory", type: :model do
  let(:bill_category_class) { Object.const_get("BillCategory") }

  describe "associations" do
    it "belongs to a bill" do
      bc = bill_category_class.new
      expect(bc).to respond_to(:bill)
    end

    it "belongs to a category" do
      bc = bill_category_class.new
      expect(bc).to respond_to(:category)
    end
  end

  describe "validations" do
    it "requires a bill" do
      category = create(:category)
      bc = bill_category_class.new(bill: nil, category: category)
      expect(bc).not_to be_valid
    end

    it "requires a category" do
      bill = create(:bill)
      bc = bill_category_class.new(bill: bill, category: nil)
      expect(bc).not_to be_valid
    end
  end

  describe "unique (bill_id, category_id) constraint" do
    it "rejects a duplicate join row (same bill + category)" do
      bill = create(:bill)
      category = create(:category)
      bill_category_class.create!(bill: bill, category: category)

      expect {
        bill_category_class.create!(bill: bill, category: category)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "allows the same category on a different bill" do
      bill1 = create(:bill)
      bill2 = create(:bill)
      category = create(:category)
      bill_category_class.create!(bill: bill1, category: category)

      expect {
        bill_category_class.create!(bill: bill2, category: category)
      }.not_to raise_error
    end

    it "allows different categories on the same bill" do
      bill = create(:bill)
      cat1 = create(:category, name: "Health")
      cat2 = create(:category, name: "Economy")
      bill_category_class.create!(bill: bill, category: cat1)

      expect {
        bill_category_class.create!(bill: bill, category: cat2)
      }.not_to raise_error
    end

    # The examples above test only the Rails uniqueness validation. This one
    # skips validation so the database's UNIQUE index is what is under test — the
    # backstop BillCategoryAssigner counts on when two requests race. Remove the
    # index from the migration and this example fails, which keeps it in place.
    it "the DB unique index rejects a duplicate even when AR validations are bypassed" do
      bill = create(:bill)
      category = create(:category)
      bill_category_class.create!(bill: bill, category: category)

      dup = bill_category_class.new(bill: bill, category: category)
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  # @lat: [[bill-category-assignment-integrity#Why BillCategory's own spec enforces no cardinality limit]]
  describe "category cardinality is enforced upstream, not by the join model" do
    it "permits a bill to hold 0 categories (uncategorized is valid — Pitfall-2)" do
      bill = create(:bill)
      expect(bill.categories.count).to eq(0)
      expect(bill).to be_valid
    end

    it "permits 1, 2, or 3 categories through the join" do
      bill = create(:bill)
      cats = create_list(:category, 3)
      cats.each { |c| bill_category_class.create!(bill: bill, category: c) }
      expect(bill.categories.count).to eq(3)
    end

    it "does NOT cap at 3 at the model layer — a 4th join row persists (the cap is " \
       "enforced by BillCategoryAssigner / Bills::CategoriesController, see their specs)" do
      bill = create(:bill)
      cats = create_list(:category, 4)
      cats.each { |c| bill_category_class.create!(bill: bill, category: c) }
      # Records the gap: the join model has no upper limit of its own.
      expect(bill.categories.count).to eq(4)
    end

    it "can query a bill's categories through the join" do
      bill = create(:bill)
      cat = create(:category, name: "Housing")
      bill_category_class.create!(bill: bill, category: cat)
      expect(bill.reload.categories).to include(cat)
    end
  end
end
