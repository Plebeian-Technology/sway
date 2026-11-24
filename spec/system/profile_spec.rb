# frozen_string_literal: true

require "rails_helper"

# @lat: [[web-profile-page#Web profile page]]
RSpec.describe "Web profile page", type: :system, js: true do
  let(:user) do
    create(:user, full_name: "Ada Lovelace").tap do |u|
      complete_registration_with_active_link(u)
    end
  end

  before do
    page.driver.browser.execute_cdp(
      "Emulation.setDeviceMetricsOverride",
      width: 1400, height: 900, deviceScaleFactor: 1, mobile: false
    )
  end

  after do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  rescue Selenium::WebDriver::Error::WebDriverError, NoMethodError
    nil
  end

  def click_drawer_link(text)
    link = find("aside", wait: 10).find_link(text, visible: :visible, wait: 10)
    page.execute_script(
      "arguments[0].scrollIntoView({block: 'center', behavior: 'instant'}); arguments[0].click();",
      link.native
    )
  end

  it "opens Profile from the navigation and follows the passkeys link" do
    sign_in_as(user)
    visit "/legislators"
    wait_until_loaded

    click_drawer_link("Profile")

    expect(page).to have_css("h1", text: "Profile", wait: 10)
    expect(page).to have_text("Ada Lovelace")

    find("[data-testid='profile-account-links']", wait: 10).click_link("Passkey Management")

    expect(page).to have_text("Passkey Management", wait: 10)
    expect(page).to have_current_path("/users/passkeys")
  end

  it "deletes the account from Profile and lands signed out on the public home page" do
    sign_in_as(user)
    visit "/profile"
    wait_until_loaded

    click_button "Delete Account"
    within("[role='dialog']", wait: 10) do
      expect(page).to have_text("This permanently removes your votes, profile, and history.")
      click_button "Delete Account"
    end

    expect(page).to have_text("Your account has been deleted.", wait: 15)
    expect(page).to have_current_path(root_path, ignore_query: true)
    expect(page).to have_button("Sign in with a passkey", wait: 10)
    expect(User.exists?(user.id)).to be(false)

    page.refresh
    wait_until_loaded
    expect(page).to have_button("Sign in with a passkey", wait: 10)

    visit "/profile"
    wait_until_loaded
    expect(page).to have_current_path(root_path, ignore_query: true, wait: 10)
    expect(page).to have_no_css("h1", text: "Profile")
  end
end
