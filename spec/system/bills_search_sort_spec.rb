# frozen_string_literal: true

require "rails_helper"

# @lat: [[bills-controller-design#Testing search, sort, and load-more interactions]]
RSpec.describe "Bills search, sort, and load more", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }

  # The database forbids two bills in the same locale from sharing a
  # scheduled_release_date_utc, so every bill here gets its own date.
  def create_titled_bills
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      title: "Alpha Housing Act",
      scheduled_release_date_utc: 3.days.ago,
      introduced_date_time_utc: 30.days.ago
    )
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      title: "Beta Transit Act",
      scheduled_release_date_utc: 5.days.ago,
      introduced_date_time_utc: 20.days.ago
    )
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      title: "Gamma Water Act",
      scheduled_release_date_utc: 7.days.ago,
      introduced_date_time_utc: 10.days.ago
    )
  end

  def expect_rendered_before(earlier_title, later_title)
    wait_until do
      text = find_by_id("app").text
      earlier = text.index(earlier_title)
      later = text.index(later_title)
      earlier && later && earlier < later
    end
  end

  it "filters bills by title through the debounced search box and encodes ?search= in the URL" do
    create_titled_bills

    visit "/bills?sway_locale_id=#{sway_locale.id}"
    expect(page).to have_text("Showing 3 bills", wait: 20)

    find("[data-testid='input-search-bills']").set("Alpha")

    # After 350ms with no typing, the page refetches just the bills and total.
    expect(page).to have_text("Alpha Housing Act", wait: 10)
    expect(page).to have_no_text("Beta Transit Act", wait: 10)
    expect(page).to have_no_text("Gamma Water Act")
    expect(page).to have_current_path(/search=Alpha/, url: true, wait: 10)

    # Emptying the box brings back the whole list and drops the URL parameter.
    # React owns this input's value, so empty it with backspaces — each one
    # fires a real input event the way a person's typing would.
    find("[data-testid='input-search-bills']").send_keys([:backspace] * 5)
    expect(page).to have_text("Showing 3 bills", wait: 10)
    expect(page).to have_no_current_path(/search=/)
  end

  it "reorders through the sort select and round-trips ?sort=&direction= in the URL" do
    create_titled_bills

    visit "/bills?sway_locale_id=#{sway_locale.id}"
    expect(page).to have_text("Showing 3 bills", wait: 20)

    # The default sort is newest introduced first, so Gamma (introduced 10 days
    # ago) comes before Alpha (30 days ago).
    expect_rendered_before("Gamma Water Act", "Alpha Housing Act")

    find("[data-testid='select-sort-bills']").select("Title A–Z")
    expect(page).to have_current_path(/sort=title/, url: true, wait: 10)
    expect(page).to have_current_path(/direction=asc/, url: true, wait: 10)
    expect_rendered_before("Alpha Housing Act", "Beta Transit Act")
    expect_rendered_before("Beta Transit Act", "Gamma Water Act")

    # Picking the default option again strips both parameters from the URL.
    find("[data-testid='select-sort-bills']").select("Newest first")
    expect_rendered_before("Gamma Water Act", "Alpha Housing Act")
    expect(page).to have_no_current_path(/sort=/)
    expect(page).to have_no_current_path(/direction=/)
  end

  it "extends the 24-bill page window with the Load more button (?page=)" do
    26.times do |i|
      create(
        :bill,
        sway_locale: sway_locale,
        legislator: legislator,
        title: format("Windowed Act %02d", i + 1),
        scheduled_release_date_utc: (i + 2).days.ago,
        introduced_date_time_utc: (i + 2).days.ago
      )
    end

    visit "/bills?sway_locale_id=#{sway_locale.id}"
    expect(page).to have_text("Showing 24 bills", wait: 20)

    find("[data-testid='btn-load-more-bills']").click

    expect(page).to have_text("Showing 26 bills", wait: 10)
    expect(page).to have_current_path(/page=2/, url: true, wait: 10)
    # Every bill is on screen now, so the button is removed.
    expect(page).to have_no_css("[data-testid='btn-load-more-bills']")
  end
end
