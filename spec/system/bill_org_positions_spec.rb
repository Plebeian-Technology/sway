# frozen_string_literal: true

require "rails_helper"

# @lat: [[organization-position-removal#What a reader sees once a position is switched off]]
RSpec.describe "Bill page organization positions", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }

  it "renders only ACTIVE positions in the support/oppose cards for a guest" do
    supporter = create(:organization, sway_locale: sway_locale, name: "Active Support Org")
    withdrawn = create(:organization, sway_locale: sway_locale, name: "Withdrawn Org")
    opposer = create(:organization, sway_locale: sway_locale, name: "Active Oppose Org")
    create(
      :organization_bill_position,
      bill: bill, organization: supporter, support: "FOR",
      summary: "We support this measure.", active: true
    )
    create(
      :organization_bill_position,
      bill: bill, organization: withdrawn, support: "FOR",
      summary: "Stale withdrawn position.", active: false
    )
    create(
      :organization_bill_position,
      bill: bill, organization: opposer, support: "AGAINST",
      summary: "We oppose this measure.", active: true
    )

    visit "/bills/#{bill.id}"

    expect(page).to have_text("Why support this bill", wait: 20)
    expect(page).to have_text("Why oppose this bill")

    expect(page).to have_text("Active Support Org")
    expect(page).to have_text("We support this measure.")
    expect(page).to have_text("Active Oppose Org")
    expect(page).to have_text("We oppose this measure.")

    # The switched-off position must not show up anywhere on the page.
    expect(page).to have_no_text("Withdrawn Org")
    expect(page).to have_no_text("Stale withdrawn position.")
  end

  it "renders only ACTIVE category tags on the bill detail page" do
    category = create(:category, name: "Transit", slug: "transit", active: true)
    retired = create(:category, name: "Retired Topic", slug: "retired-topic", active: false)
    create(:bill_category, bill: bill, category: category)
    create(:bill_category, bill: bill, category: retired)

    visit "/bills/#{bill.id}"

    # The detail page has no row of category filter buttons, so this text can
    # only be coming from the category tags in the bill header.
    expect(find_by_id("app", wait: 10)).to have_text("Transit", wait: 20)
    expect(page).to have_no_text("Retired Topic")
  end
end
