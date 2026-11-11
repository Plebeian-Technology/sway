# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My Organizations dashboard", type: :system, js: true do
  let(:user) do
    create(:user).tap do |u|
      complete_registration_with_active_link(u)
    end
  end

  it "renders one tile per active membership" do
    organization = create(:organization)
    create(
      :user_organization_membership,
      user: user,
      organization: organization,
      status: "active"
    )

    # sign_in_as only opens the session; admin status comes from the phone.
    sign_in_as(user)
    visit "/users/organization_memberships"
    wait_until_loaded

    expect(page).to have_css(
      "[data-testid='my-organizations-heading']",
      text: "My Organizations",
      wait: 10
    )
    expect(page).to have_css("[data-testid='membership-card']", count: 1, wait: 10)
    expect(find("[data-testid='membership-card']")).to have_text(organization.name)
    expect(page).to have_no_css("[data-testid='my-organizations-empty']")
  end

  it "renders the empty state for a user with no memberships" do
    sign_in_as(user)
    visit "/users/organization_memberships"
    wait_until_loaded

    expect(page).to have_css("[data-testid='my-organizations-empty']", wait: 10)
    expect(page).to have_css(
      "[data-testid='my-organizations-heading']",
      text: "My Organizations"
    )
    expect(page).to have_no_css("[data-testid='membership-card']")
  end
end
