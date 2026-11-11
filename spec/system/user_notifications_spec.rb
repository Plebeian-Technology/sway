# frozen_string_literal: true

require "rails_helper"

# @lat: [[notifications-tab-url#The Notifications tab in the URL]]
RSpec.describe "User Notifications", type: :system, js: true, phase16: true do
  let(:sway_locale) do
    SwayLocale.find_by(
      city: "baltimore",
      state: "MD",
      country: "United States"
    ) ||
      create(
        :sway_locale,
        city: "baltimore",
        state: "MD",
        country: "United States"
      )
  end
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }

  before do
    @signed_in_user = create(:user, phone: "4105550099")
    address =
      create(
        :address,
        city: "baltimore",
        region_code: "MD",
        country: "United States"
      )
    create(:user_address, user: @signed_in_user, address: address)
    create(:user_legislator, user: @signed_in_user, legislator: legislator)
    sign_in_as(@signed_in_user)
  end

  # The fake service worker lives in spec/support/service_worker_stub.rb and is
  # mixed into every spec through RSpec.configure.

  it "renders Enable Notifications button when user has no push subscription" do
    visit "/notifications"
    wait_until_loaded

    expect(page).to have_button("Enable push notifications on this device")
  end

  it "renders Disable Notifications button when user already has a push subscription" do
    endpoint = "https://fcm.googleapis.com/fcm/send/TEST-EXISTING-789"
    create(
      :push_notification_subscription,
      user: @signed_in_user,
      endpoint: endpoint,
      subscribed: true
    )

    inject_service_worker_stub!(endpoint: endpoint)

    visit "/notifications"
    wait_until_loaded

    expect(page).to have_button("Disable on this device")
  end

  it "switches between Push and SMS tabs via in-page clicks and mirrors the URL" do
    visit "/notifications"
    wait_until_loaded

    # Starts on Push tab by default
    expect(page).to have_button("Enable push notifications on this device")
    expect(page).to have_no_css("[aria-busy='true']")

    # Click SMS tab
    find("[role='tab']", text: "SMS").click
    expect(page).to have_current_path("/notifications?notifications_tab=sms")
    expect(page).to have_css("[data-testid='notification-sms-toggle']")

    # Click Push tab
    find("[role='tab']", text: "Push").click
    expect(page).to have_current_path("/notifications?notifications_tab=push")
    expect(page).to have_button("Enable push notifications on this device")
  end

  it "selects SMS tab from legacy tab=sms parameter and updates to canonical parameter on subsequent navigation" do
    visit "/notifications?tab=sms"
    wait_until_loaded

    expect(page).to have_css("[data-testid='notification-sms-toggle']")

    find("[role='tab']", text: "Push").click
    expect(page).to have_current_path("/notifications?notifications_tab=push")
    expect(page).to have_no_current_path(/tab=sms/)
  end

  it "defaults to the SMS tab when push notifications are unsupported" do
    result = page.driver.browser.execute_cdp(
      "Page.addScriptToEvaluateOnNewDocument",
      source: "delete window.PushManager; delete window.Notification;"
    )
    script_id = result["identifier"] if result.is_a?(Hash)

    begin
      visit "/notifications"
      wait_until_loaded

      expect(page).to have_css("[data-testid='notification-sms-toggle']")
    ensure
      if script_id
        page.driver.browser.execute_cdp(
          "Page.removeScriptToEvaluateOnNewDocument",
          identifier: script_id
        )
      end
    end
  end
end
