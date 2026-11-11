# frozen_string_literal: true

require "rails_helper"

# @lat: [[bills-controller-design#Testing the bills filter against real server props]]
RSpec.describe "Bills filter", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }

  let!(:health_cat) { create(:category, name: "Health", slug: "health", active: true) }
  let!(:housing_cat) { create(:category, name: "Housing", slug: "housing", active: true) }

  # @lat: [[bills-controller-design#Testing the bills filter against real server props]]
  let(:bill_a) do
    create(:bill, sway_locale: sway_locale, legislator: legislator, title: "Alpha Health Bill",
      scheduled_release_date_utc: 3.days.ago)
  end
  let(:bill_b) do
    create(:bill, sway_locale: sway_locale, legislator: legislator, title: "Beta Housing Bill",
      scheduled_release_date_utc: 5.days.ago)
  end
  let(:bill_c) do
    create(:bill, sway_locale: sway_locale, legislator: legislator, title: "Gamma Multi Bill",
      scheduled_release_date_utc: 7.days.ago)
  end

  before do
    # Naming each bill is what creates it, so the bills and their category
    # links all exist before the page is visited.
    bill_a
    bill_b
    bill_c
    create(:bill_category, bill: bill_a, category: health_cat)
    create(:bill_category, bill: bill_b, category: housing_cat)
    create(:bill_category, bill: bill_c, category: health_cat)
    create(:bill_category, bill: bill_c, category: housing_cat)
  end

  # Visit /bills pinned to this test's locale so the page shows our bills.
  def visit_bills
    visit "/bills?sway_locale_id=#{sway_locale.id}"
    # Wait for the first render and for the bills prop, which Inertia fetches in
    # a second request, so "Showing N bills" is on the page before we check it.
    expect(page).to have_text("Showing", wait: 20)
  end

  it "lists options from the server all_categories prop (snake_case wire-name smoke)" do
    visit_bills
    open_category_filter

    # The options come from Category.where(active: true).pluck(:name) and print
    # each name exactly as stored; nothing re-capitalizes it. If the frontend
    # read `allCategories` instead of `all_categories`, the prop would be
    # undefined and the list would be empty. This check catches that.
    expect(page).to have_field("Health", type: :checkbox, wait: 10)
    expect(page).to have_field("Housing", type: :checkbox, wait: 10)
  end

  it "(a) no category selected → all bills render" do
    visit_bills

    expect(page).to have_text("Showing 3 bills", wait: 10)
    expect(page).to have_text("Alpha Health Bill")
    expect(page).to have_text("Beta Housing Bill")
    expect(page).to have_text("Gamma Multi Bill")
  end

  it "(b) one category selected → only matching bills remain" do
    visit_bills

    toggle_category "Health"
    # A bill stays if it has ANY picked category: bill_a (health) ✓; bill_b (housing only) ✗; bill_c (both) ✓
    expect(page).to have_text("Showing 2 bills", wait: 10)
    expect(page).to have_text("Alpha Health Bill")
    expect(page).to have_no_text("Beta Housing Bill")
    expect(page).to have_text("Gamma Multi Bill")
  end

  it "(c) two categories selected → OR union of both (a bill matching either appears)" do
    visit_bills

    toggle_category "Health"
    toggle_category "Housing"

    expect(page).to have_text("Showing 3 bills", wait: 10)
    expect(page).to have_text("Alpha Health Bill")
    expect(page).to have_text("Beta Housing Bill")
    expect(page).to have_text("Gamma Multi Bill")
  end

  it "(d) deselect the category → full list returns" do
    visit_bills

    toggle_category "Health"
    expect(page).to have_text("Showing 2 bills", wait: 10)

    toggle_category "Health"
    expect(page).to have_text("Showing 3 bills", wait: 10)
    expect(page).to have_text("Alpha Health Bill")
    expect(page).to have_text("Beta Housing Bill")
    expect(page).to have_text("Gamma Multi Bill")
  end
end
