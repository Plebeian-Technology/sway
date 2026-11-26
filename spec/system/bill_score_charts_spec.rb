# frozen_string_literal: true

require "rails_helper"

# @lat: [[query-plan-indexes#Index shapes the query planner can use#A query-cost guard measures growth, not a ceiling]]
# @lat: [[scores-and-agreement#Scores and agreement#The five score families]]
RSpec.describe "Bill score charts", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:bill) do
    create(
      :bill,
      sway_locale:,
      title: "Charted bill",
      scheduled_release_date_utc: Time.zone.today
    )
  end

  # District 1 has twelve split voters. District 2 has five voters and district 3 is unanimous.
  def tally(bill_for:, bill_against:)
    score = bill.bill_score
    score.update!(for: bill_for, against: bill_against)

    {1 => [9, 3], 2 => [4, 1], 3 => [11, 0]}.each do |number, (district_for, district_against)|
      district = create(:district, sway_locale:, name: "District #{number}")
      create(:bill_score_district, bill_score: score, district:, for: district_for, against: district_against)
    end
  end

  # @lat: [[voter-privacy-threshold#Percentages are rounded to steps and a unanimous split is withheld]]
  def expect_rounded_percentages
    expect(page).to have_css("[data-testid='total-votes-chart'] [aria-label='65% support, 35% oppose']", wait: 10)
    expect(page).to have_css("[data-testid='district-votes-chart']")
    expect(page).to have_css("[data-testid='affinity-district-chart']")
    expect(page).to have_css("[aria-label='District 1 support 80%']")
    expect(page).to have_css("[aria-label='District 1 oppose 20%']")
    expect(page).to have_text("D-1 (+60%)")
    expect(page).to have_no_css("[aria-label^='District 2']")
    expect(page).to have_no_css("[aria-label^='District 3']")
    expect(page).to have_no_text("D-2")
    expect(page).to have_no_text("D-3")
    expect(page).to have_no_text("Not enough votes yet")
  end

  # @lat: [[voter-privacy-threshold#The web bill page asks one helper whether to draw a comparison]]
  def expect_placeholder_instead_of_charts
    expect(page).to have_text("Not enough votes yet", count: 1, wait: 10)
    expect(page).to have_text("Invite others by sharing Sway")
    expect(page).to have_no_text("Visual comparisons will be shown")
    expect(page).to have_no_css("[data-testid^='total-votes-chart']")
    expect(page).to have_no_css("[data-testid^='district-votes-chart']")
    expect(page).to have_no_css("[data-testid^='affinity-district-chart']")
    expect(page).to have_no_css("[aria-label^='District 1']")
    expect(page).to have_no_text("D-1")
  end

  def bill_of_the_month_path
    "/bill_of_the_month?sway_locale_id=#{sway_locale.id}"
  end

  it "shows rounded percentages on the bill page for a split bill with thirty votes" do
    tally(bill_for: 20, bill_against: 10)

    visit bill_path(bill)

    expect(page).to have_text("Charted bill")
    expect_rounded_percentages
  end

  it "shows rounded percentages on the Bill of the Month page for a split bill with thirty votes" do
    tally(bill_for: 20, bill_against: 10)

    visit bill_of_the_month_path

    expect(page).to have_text("Charted bill")
    expect_rounded_percentages
  end

  it "shows the placeholder on the bill page for a bill with nine votes" do
    tally(bill_for: 6, bill_against: 3)

    visit bill_path(bill)

    expect(page).to have_text("Charted bill")
    expect_placeholder_instead_of_charts
  end

  it "shows the placeholder on the Bill of the Month page for a bill with nine votes" do
    tally(bill_for: 6, bill_against: 3)

    visit bill_of_the_month_path

    expect(page).to have_text("Charted bill")
    expect_placeholder_instead_of_charts
  end

  it "shows the same placeholder on the bill page for a unanimous bill with thirty votes" do
    tally(bill_for: 30, bill_against: 0)

    visit bill_path(bill)

    expect(page).to have_text("Charted bill")
    expect_placeholder_instead_of_charts
  end

  it "shows the same placeholder on the Bill of the Month page for a unanimous bill with thirty votes" do
    tally(bill_for: 30, bill_against: 0)

    visit bill_of_the_month_path

    expect(page).to have_text("Charted bill")
    expect_placeholder_instead_of_charts
  end
end
