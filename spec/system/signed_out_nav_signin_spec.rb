# frozen_string_literal: true

require "rails_helper"

# @lat: [[system-shape#Auth navigation]]
RSpec.describe "Signed-out nav sign-in link", type: :system, js: true do
  let(:sway_locale) do
    SwayLocale.find_by(city: "baltimore", state: "MD", country: "United States") ||
      create(:sway_locale, city: "baltimore", state: "MD", country: "United States")
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

  it "navigates from a public page to the sign-in page when clicking the nav link" do
    create(:organization, sway_locale: sway_locale, name: "Civic Org")

    visit public_organizations_path

    expect(find_by_id("app", wait: 10)).to have_text("Civic Org")

    click_drawer_link("Sign in to Sway")

    expect(page).to have_current_path(root_path, ignore_query: true, wait: 10)
    expect(page).to have_text("Remember in November.", wait: 10)
    expect(page).to have_button("Sign in with a passkey", wait: 10)
  end
end
