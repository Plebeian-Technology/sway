# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislators-tab-switching-design#Why Legislators.tsx switches tabs without a server round trip]]
RSpec.describe "Legislators index navigation", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) do
    create(:legislator, district: district).tap do |l|
      l.update!(email: "rep@example.com")
      # LegislatorsController#json_legislators now returns only legislators who
      # are currently serving, which it works out from their terms. Give this
      # one a term so it shows up in the list.
      create(:legislator_term, legislator: l, district: district)
    end
  end

  it "navigates from the index card's View representative link to the detail page" do
    user = create(:user)
    create(:user_legislator, user: user, legislator: legislator, active: true)
    user.complete!

    sign_in_as(user)
    visit "/legislators?sway_locale_id=#{sway_locale.id}"
    wait_until_loaded

    expect(page).to have_text("Representatives", wait: 10)
    expect(page).to have_text(legislator.full_name)
    # The card's link points at the one-segment path.
    expect(page).to have_link("View representative", href: "/legislators/#{legislator.id}")

    click_link "View representative"
    wait_until_loaded

    expect(page).to have_css("[data-testid='legislator-detail-contact']", wait: 10)
    expect(page).to have_css("h1", text: legislator.full_name)
    expect(page).to have_css("[data-testid='legislator-detail-email']")
    expect(page).to have_current_path("/legislators/#{legislator.id}", ignore_query: true)
  end
end
