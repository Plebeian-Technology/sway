# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-categories-spec#The smoke-test fallback for the admin screens]]
RSpec.describe "Admin Categories",
  type: :system,
  js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:sway_admin_user) { create(:user, :sway_admin) }

  before { create(:user_legislator, user: sway_admin_user, legislator: legislator) }

  describe "taxonomy page" do
    it "renders the page heading and section titles (smoke)" do
      sign_in_as(sway_admin_user)

      visit "/admin/categories"
      wait_until_loaded

      expect(page).to have_text("Category Taxonomy")
      expect(page).to have_text("Manage categories for bill classification.")
      # The card heading changed from "Active categories" to "Categories"
      # because the table shows every category, with the inactive ones badged,
      # not only the active ones.
      expect(page).to have_text("Categories")
      expect(page).to have_text("Add category")
    end
  end

  describe "ADD — add a new category via the add form" do
    it "shows the new category in the table after submission" do
      sign_in_as(sway_admin_user)

      visit "/admin/categories"
      wait_until_loaded

      fill_in "New category name", with: "Test Environment"
      click_button "Add category"
      wait_until_loaded

      expect(page).to have_text("Category added.", wait: 10)
      expect(page).to have_text("Test Environment")

      expect(Category.find_by(name: "Test Environment")).to be_present
    end
  end

  # @lat: [[toasts#Flash toast dedupe]]
  describe "ADD — two adds in a row, each producing the same confirmation" do
    it "confirms the second add as well as the first" do
      sign_in_as(sway_admin_user)

      visit "/admin/categories"
      wait_until_loaded

      fill_in "New category name", with: "First Topic"
      click_button "Add category"

      expect(page).to have_text("Category added.", wait: 10)
      expect(page).to have_no_text("Category added.", wait: 20)

      fill_in "New category name", with: "Second Topic"
      click_button "Add category"

      expect(page).to have_text("Category added.", wait: 10)
      expect(Category.find_by(name: "Second Topic")).to be_present
    end
  end

  describe "RENAME — rename a category inline" do
    let!(:category) { create(:category, name: "Original Name") }

    it "updates the displayed name and shows the flash notice" do
      sign_in_as(sway_admin_user)

      visit "/admin/categories"
      wait_until_loaded

      expect(page).to have_text("Original Name")

      within("tr", text: "Original Name") do
        click_button "Rename"
      end

      rename_input = find("input[aria-label='Rename Original Name']")
      rename_input.set("Renamed Category")

      click_button "Save name"
      wait_until_loaded

      expect(page).to have_text("Category renamed.", wait: 10)
      expect(page).to have_text("Renamed Category")

      expect(category.reload.name).to eq("Renamed Category")
    end
  end

  describe "DEACTIVATE — soft-deactivate preserves bill↔category join rows" do
    let!(:category) { create(:category, name: "Housing Policy", slug: "housing-policy", active: true) }
    let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }
    let!(:bill_category_join) { create(:bill_category, bill: bill, category: category) }

    it "flips status to Inactive while the join row survives (R7 — locked soft-removal)" do
      expect(BillCategory.where(category: category).count).to eq(1)

      sign_in_as(sway_admin_user)

      visit "/admin/categories"
      wait_until_loaded

      expect(page).to have_text("Housing Policy")

      within("tr", text: "Housing Policy") do
        click_button "Deactivate"
      end

      expect(page).to have_text("Deactivate category?", wait: 5)
      expect(page).to have_text("Existing bill assignments are preserved.")

      find("[role='dialog']").click_button("Deactivate")
      wait_until_loaded

      expect(page).to have_text("Category deactivated.", wait: 10)

      # The link row SURVIVES — deactivating removes nothing, by design
      expect(BillCategory.where(category: category).count).to eq(1)

      expect(category.reload.active).to be(false)
    end
  end

  # Permanent deletion is only offered on a row that has already been
  # deactivated, so removing a category takes two steps. Deleting also removes
  # the matching bill_categories link rows, so a category still assigned to
  # bills has those links cleared away.
  describe "DELETE — permanently delete a deactivated category" do
    let!(:category) { create(:category, name: "Retired Topic", slug: "retired-topic", active: false) }
    let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }
    let!(:bill_category_join) { create(:bill_category, bill: bill, category: category) }

    it "removes the row, the record, and its join rows after confirm" do
      expect(BillCategory.where(category: category).count).to eq(1)

      sign_in_as(sway_admin_user)

      visit "/admin/categories"
      wait_until_loaded

      expect(page).to have_text("Retired Topic")

      within("tr", text: "Retired Topic") do
        click_button "Delete"
      end

      expect(page).to have_text("Delete category?", wait: 5)
      expect(page).to have_text("removes it from 1 bill")

      find("[role='dialog']").click_button("Delete")
      wait_until_loaded

      expect(page).to have_text("Category deleted.", wait: 10)
      # The row is gone, so the table shows its empty state. Look for that
      # empty state rather than `not_to have_content("Retired Topic")`, which
      # would also match the serialized Inertia page data inside page.text.
      expect(page).to have_text("No categories found.")

      expect(Category.find_by(id: category.id)).to be_nil
      expect(BillCategory.where(category_id: category.id).count).to eq(0)
    end
  end
end
