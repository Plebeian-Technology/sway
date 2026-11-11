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

  before do
    score = bill.bill_score
    score.update!(for: 7, against: 3)

    [1, 2].each do |number|
      district = create(:district, sway_locale:, name: "District #{number}")
      create(:bill_score_district, bill_score: score, district:, for: number + 2, against: 1)
    end
  end

  def expect_populated_charts
    expect(page).to have_css("[data-testid='total-votes-chart']", wait: 10)
    expect(page).to have_css("[data-testid='district-votes-chart']")
    expect(page).to have_css("[data-testid='affinity-district-chart']")
    expect(page).to have_css("[data-testid='total-votes-chart'] [aria-label='7 support, 3 oppose']")
    expect(page).to have_css("[aria-label='District 1 support 3']")
    expect(page).to have_css("[aria-label='District 2 support 4']")
    expect(page).to have_text("D-1 (+2)")
    expect(page).to have_text("D-2 (+3)")
  end

  it "renders populated score charts on the bill page" do
    visit bill_path(bill)

    expect(page).to have_text("Charted bill")
    expect_populated_charts
  end

  it "renders populated score charts on the Bill of the Month page" do
    visit "/bill_of_the_month?sway_locale_id=#{sway_locale.id}"

    expect(page).to have_text("Charted bill")
    expect_populated_charts
  end
end
