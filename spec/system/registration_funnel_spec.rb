# frozen_string_literal: true

require "rails_helper"

# @lat: [[registration-funnel-telemetry#Admin registration funnel dashboard]]
# @lat: [[registration-funnel-telemetry#Client-side telemetry dispatch and step mapping]]
# @lat: [[registration-funnel-telemetry#Ingestion API and rate limiting]]
RSpec.describe "Registration funnel admin", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale:) }
  let(:legislator) { create(:legislator, district:) }
  let(:sway_admin_user) { create(:user, :sway_admin) }

  before do
    create(:user_legislator, user: sway_admin_user, legislator:)

    # Seed funnel events
    RegistrationFunnelEvent.create!(
      visitor_token: "v-system-1",
      step: :landing,
      attribution_key: "s:campaign_fall",
      created_at: 1.day.ago
    )
    RegistrationFunnelEvent.create!(
      visitor_token: "v-system-1",
      step: :phone_submitted,
      attribution_key: "s:campaign_fall",
      created_at: 1.day.ago
    )
    RegistrationFunnelEvent.create!(
      visitor_token: "v-system-1",
      step: :geocoding_completed,
      attribution_key: "s:campaign_fall",
      created_at: 1.day.ago,
      metadata: {"latency_ms" => 1450.0}
    )
  end

  it "displays Registration Funnel card on /admin and navigates to the dashboard" do
    sign_in_as(sway_admin_user)
    visit "/admin"
    wait_until_loaded

    expect(page).to have_text("Registration Funnel", wait: 10)
    expect(page).to have_text("Analyze voter registration conversion rates, drop-off friction points, and referral source attribution.")

    click_link "Registration Funnel"
    wait_until_loaded

    expect(page).to have_text("Registration Funnel", wait: 10)
    expect(page).to have_text("Landing Visitors")
    expect(page).to have_text("Phone Entered")
    expect(page).to have_text("Async Geocoding Latency")
  end

  it "renders dashboard directly at /admin/registration_funnel" do
    sign_in_as(sway_admin_user)
    visit "/admin/registration_funnel"
    wait_until_loaded

    expect(page).to have_text("Registration Funnel", wait: 10)
    expect(page).to have_text("Landing Page")
    expect(page).to have_text("Top Friction Points")
    expect(page).to have_text("Referral Source Attribution")
  end

  it "renders without horizontal overflow on 390px and 320px viewports and supports attribution filter inspection" do
    page.current_window.resize_to(390, 844)
    sign_in_as(sway_admin_user)
    visit "/admin/registration_funnel"
    wait_until_loaded

    expect(page.evaluate_script("document.documentElement.scrollWidth")).to be <= page.evaluate_script("window.innerWidth") + 1
    first("button", text: "Inspect").click
    wait_until_loaded
    expect(find("button", text: "Clear Filter")).to be_visible

    page.current_window.resize_to(320, 568)
    visit "/admin/registration_funnel"
    wait_until_loaded
    expect(page.evaluate_script("document.documentElement.scrollWidth")).to be <= page.evaluate_script("window.innerWidth") + 1
  end

  it "emits landing and phone_submitted client telemetry beacons without raw PII and deduplicates landing per session" do
    reset_browser_state
    page.current_window.resize_to(1400, 900)
    visit root_path
    wait_until_loaded

    wait_until { RegistrationFunnelEvent.where(step: :landing).exists? }
    initial_landing_count = RegistrationFunnelEvent.where(step: :landing).count

    visit root_path
    wait_until_loaded
    expect(RegistrationFunnelEvent.where(step: :landing).count).to eq(initial_landing_count)

    test_phone = "4105550199"
    fill_in "v2-phone", with: test_phone
    click_button "Continue with Phone"
    wait_until { RegistrationFunnelEvent.where(step: :phone_submitted).exists? }

    phone_event = RegistrationFunnelEvent.where(step: :phone_submitted).last
    expect(phone_event.metadata.to_s).not_to include(test_phone)
  end
end
