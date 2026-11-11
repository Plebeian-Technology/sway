# frozen_string_literal: true

require "rails_helper"

# Three rules: only active categories may be assigned, a bill gets 1-3, and
# names match by slug. Nothing matching raises Llm::SchemaError; the caller
# discards the bill from there.
RSpec.describe "BillCategoryAssigner", type: :model do
  # Look the class up by name so this file still loads if the class is missing.
  let(:assigner_class) { Object.const_get("BillCategoryAssigner") }
  let(:schema_error_class) { Object.const_get("Llm::SchemaError") }

  let(:bill) { create(:bill) }

  # The set these examples work with: five stand-in categories.
  let!(:cat_civil_rights) { create(:category, name: "Civil Rights", slug: "civil-rights", active: true) }
  let!(:cat_housing) { create(:category, name: "Housing", slug: "housing", active: true) }
  let!(:cat_health) { create(:category, name: "Health", slug: "health", active: true) }
  let!(:cat_economy) { create(:category, name: "Economy", slug: "economy", active: true) }
  let!(:cat_inactive) { create(:category, name: "Deprecated", slug: "deprecated", active: false) }

  let(:active_categories) { [cat_civil_rights, cat_housing, cat_health, cat_economy] }

  describe "#call — happy path: assigns 1–3 active categories" do
    it "creates BillCategory join rows for matched active categories" do
      raw_names = ["Civil Rights", "Housing"]
      assigner_class.new(bill, raw_names, active_categories).call
      expect(bill.categories.count).to be_between(1, 3)
      expect(bill.categories.map(&:name)).to include("Civil Rights", "Housing")
    end

    it "returns the matched Category records" do
      raw_names = ["Health"]
      result = assigner_class.new(bill, raw_names, active_categories).call
      expect(result).to be_an(Array)
      expect(result.map(&:name)).to include("Health")
    end

    it "all returned categories are members of the active set" do
      raw_names = ["Civil Rights", "Housing", "Health"]
      assigner_class.new(bill, raw_names, active_categories).call
      expect(bill.categories).to all(satisfy { |c| c.active? })
    end
  end

  describe "#call — active-subset-only enforcement" do
    it "drops names NOT in the active set — they are never persisted" do
      raw_names = ["Deprecated", "Civil Rights"]  # "Deprecated" is inactive
      assigner_class.new(bill, raw_names, active_categories).call
      expect(bill.categories.map(&:name)).not_to include("Deprecated")
    end

    it "drops completely unknown names — they are never persisted" do
      raw_names = ["NonExistentCategory", "Civil Rights"]
      assigner_class.new(bill, raw_names, active_categories).call
      expect(bill.categories.map(&:name)).not_to include("NonExistentCategory")
    end

    it "raises Llm::SchemaError when ALL raw names are outside the active set" do
      raw_names = ["Deprecated", "NonExistentCategory"]
      expect {
        assigner_class.new(bill, raw_names, active_categories).call
      }.to raise_error(schema_error_class)
    end

    it "raises Llm::SchemaError when raw_names is empty" do
      expect {
        assigner_class.new(bill, [], active_categories).call
      }.to raise_error(schema_error_class)
    end
  end

  describe "#call — cardinality: more than 3 valid names truncated to first(3)" do
    it "assigns at most 3 categories even when 4+ match the active set" do
      raw_names = ["Civil Rights", "Housing", "Health", "Economy"]  # 4 valid names
      assigner_class.new(bill, raw_names, active_categories).call
      expect(bill.categories.count).to eq(3)
    end
  end

  # A repeated name must not eat one of the three slots — duplicates are
  # removed before taking the first 3, so a repeat doesn't cost a slot.
  describe "#call — WR-01 dedup: duplicate LLM names do not consume cap slots" do
    it "persists 3 DISTINCT categories when LLM returns a duplicate name and 3 unique valid names" do
      # Without .uniq, first(3) of this list gives only 2 distinct categories;
      # with .uniq it gives the intended 3.
      raw_names = ["Health", "Health", "Housing", "Education"]
      cat_education = create(:category, name: "Education", slug: "education", active: true)
      assigner_class.new(bill, raw_names, active_categories + [cat_education]).call
      expect(bill.reload.categories.count).to eq(3)
      expect(bill.reload.categories.map(&:name)).to include("Health", "Housing", "Education")
    end
  end

  describe "#call — idempotency: find_or_create_by!, no duplicate rows" do
    it "re-calling does not duplicate BillCategory join rows" do
      raw_names = ["Civil Rights", "Housing"]
      assigner_class.new(bill, raw_names, active_categories).call
      first_count = bill.categories.count

      assigner_class.new(bill, raw_names, active_categories).call
      expect(bill.reload.categories.count).to eq(first_count)
    end
  end

  # The limit of 3 categories per bill holds across repeated .call runs. The
  # assigner only adds rows and never removes existing ones, but the running
  # total must still never go above 3.
  describe "#call — CR-01 cross-run cap: total never exceeds 3" do
    it "does not add categories when the bill already has 3 (second call is a no-op)" do
      # Fill the bill to the limit by hand, standing in for an earlier run or an
      # admin's own choice.
      BillCategory.create!(bill: bill, category: cat_civil_rights)
      BillCategory.create!(bill: bill, category: cat_housing)
      BillCategory.create!(bill: bill, category: cat_health)
      expect(bill.reload.categories.count).to eq(3)

      # A second call with a NEW category must not push past 3.
      assigner_class.new(bill, ["Economy"], active_categories).call
      expect(bill.reload.categories.count).to eq(3)
    end

    it "total never exceeds 3 across two calls with different matched sets" do
      # First call assigns 2 categories.
      assigner_class.new(bill, ["Civil Rights", "Housing"], active_categories).call
      expect(bill.reload.categories.count).to eq(2)

      # Second call with 2 new names: only 1 more slot remains.
      assigner_class.new(bill, ["Health", "Economy"], active_categories).call
      expect(bill.reload.categories.count).to eq(3)
    end
  end

  # Inactive rows must not count toward the limit of 3, or a bill whose
  # categories got deactivated could never gain new active ones.
  describe "#call — B-W-01: inactive rows do not consume the active ≤3 cap" do
    let!(:inactive_a) { create(:category, name: "Old A", slug: "old-a", active: false) }
    let!(:inactive_b) { create(:category, name: "Old B", slug: "old-b", active: false) }
    let!(:inactive_c) { create(:category, name: "Old C", slug: "old-c", active: false) }

    it "assigns active categories even when the bill already carries 3 inactive-category rows" do
      [inactive_a, inactive_b, inactive_c].each { |c| BillCategory.create!(bill: bill, category: c) }
      expect(bill.reload.bill_categories.count).to eq(3)

      assigner_class.new(bill, ["Civil Rights", "Housing"], active_categories).call

      active_names = bill.reload.categories.select(&:active?).map(&:name)
      expect(active_names).to include("Civil Rights", "Housing")
    end

    it "caps the ACTIVE count at 3 independent of pre-existing inactive rows" do
      BillCategory.create!(bill: bill, category: inactive_a)

      # 4 active matches, but only 3 are saved; the inactive row is left alone.
      assigner_class.new(bill, ["Civil Rights", "Housing", "Health", "Economy"], active_categories).call

      expect(bill.reload.categories.count(&:active?)).to eq(3)
      expect(bill.reload.bill_categories.count).to eq(4) # 3 active + 1 pre-existing inactive
    end
  end

  describe "#call — slug matching: case/space/ampersand-insensitive" do
    # The lookup table built in memory is keyed on Category.slugify(c.name), the
    # category's current name, not on the stored slug, which never changes. That
    # keeps matching correct after a rename.
    it "matches 'civil rights' (lowercase) to 'Civil Rights' active category" do
      raw_names = ["civil rights"]
      assigner_class.new(bill, raw_names, active_categories).call
      expect(bill.categories.map(&:name)).to include("Civil Rights")
    end

    it "matches 'CIVIL RIGHTS' (uppercase) to 'Civil Rights' active category" do
      raw_names = ["CIVIL RIGHTS"]
      assigner_class.new(bill, raw_names, active_categories).call
      expect(bill.categories.map(&:name)).to include("Civil Rights")
    end

    it "matches 'Budget & Taxes' (with ampersand) slug-normalized to active category" do
      cat_budget = create(:category, name: "Budget & Taxes", slug: "budget-taxes", active: true)
      raw_names = ["budget & taxes"]
      assigner_class.new(bill, raw_names, active_categories + [cat_budget]).call
      expect(bill.categories.map(&:name)).to include("Budget & Taxes")
    end
  end

  describe "#call — rename × assignment contract (60-09 cross-reference)" do
    # The lookup keys on Category.slugify(c.name), the current name, not
    # c.slug, which stays frozen at the old value — that would make a renamed
    # category quietly stop matching forever.
    it "assigns when LLM returns the new name after a category is renamed" do
      cat_health.update!(name: "Healthcare")  # stored slug stays "health"; name is now "Healthcare"
      raw_names = ["Healthcare"]

      assigner_class.new(bill, raw_names, active_categories).call
      expect(bill.categories.map(&:name)).to include("Healthcare")
    end
  end

  # Every caller depends on this: when the active set is empty the assigner
  # raises, so the caller can skip or guard rather than save a completed
  # bill with no categories.
  describe "#call — empty active set (WR-03 contract)" do
    it "raises Llm::SchemaError when active_categories is empty" do
      expect {
        assigner_class.new(bill, ["Health"], []).call
      }.to raise_error(schema_error_class)
    end
  end
end
