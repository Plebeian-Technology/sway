# frozen_string_literal: true

require "rails_helper"

# @lat: [[capybara-app-element-render-check#Why some system specs scope assertions to the app element]]
# These examples cover what a signed-out visitor sees. Following an
# organization and the notifications that come with it — Follow and Unfollow,
# the preferences picker, member badges — live in organization_follows_spec.rb.
RSpec.describe "Public Organizations", type: :system, js: true do
  let(:sway_locale) do
    SwayLocale.find_by(city: "baltimore", state: "MD", country: "United States") ||
      create(:sway_locale, city: "baltimore", state: "MD", country: "United States")
  end

  it "renders the organization list for a guest" do
    create(:organization, sway_locale: sway_locale, name: "Browseable Civic Org")

    visit public_organizations_path

    # Look only at the text React rendered, so a match against the JSON
    # embedded in the page cannot fake a pass.
    expect(find_by_id("app", wait: 10)).to have_text("Browseable Civic Org")
    expect(page).to have_css("[data-testid='public-organization-card']", wait: 10)
  end

  it "renders an organization's detail page with its positions" do
    organization = create(:organization, sway_locale: sway_locale, name: "Detailed Org")
    create(
      :organization_bill_position,
      organization: organization,
      support: "FOR",
      active: true,
      summary: "We support this measure."
    )

    visit public_organization_path(organization)

    detail = find("[data-testid='public-organization-detail']", wait: 10)
    expect(detail).to have_text("Detailed Org")
    expect(detail).to have_css("[data-testid='public-organization-position']")
    expect(detail).to have_text("We support this measure.")
  end

  it "renders the copy-constant empty state when an organization has no positions" do
    organization = create(:organization, sway_locale: sway_locale, name: "Quiet Org")

    visit public_organization_path(organization)

    empty_state = find("[data-testid='public-organization-positions-empty']", wait: 10)
    expect(empty_state).to have_text("This organization hasn't published any positions yet.")
  end

  it "renders the stamped-status badge with a real inset ring" do
    organization = create(:organization, sway_locale: sway_locale, name: "Ringed Org")
    create(
      :organization_bill_position,
      organization: organization,
      support: "FOR",
      active: true,
      summary: "We support this measure."
    )

    visit public_organization_path(organization)

    badge = find(
      "[data-testid='public-organization-position'] [data-slot='badge'][data-variant='stamp']",
      wait: 10
    )
    # @lat: [[theme-tokens#Why some rules are read from the computed style]]
    box_shadow = page.evaluate_script("getComputedStyle(arguments[0]).boxShadow", badge)
    expect(box_shadow).to include("inset")
    expect(box_shadow).not_to eq("none")
  end
end
