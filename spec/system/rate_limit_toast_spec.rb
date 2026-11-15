# frozen_string_literal: true

require "rails_helper"

# @lat: [[rate-limit-toast-spec-design#How the spec triggers a real 429]]
RSpec.describe "Rate limit throttle toast", type: :system, js: true do
  around do |example|
    # The server runs in a thread of this same process, so the swapped
    # setting is visible to it (the same property with_rate_limit_enabled
    # relies on below).
    with_app_config(:dev_login, skip_phone_verification: true) { example.run }
  end

  it "shows the throttle toast and latches the submit button on a real 429" do
    visit root_path
    expect(page).to have_button("Continue with Phone", wait: 10)

    with_rate_limit_enabled(:sign_in) do
      # Blow past the per-IP sign-in limit of 10 in 5 minutes, so the submit
      # below is rejected no matter how the per-phone limit is counted.
      10.times do
        browser_json_request("POST", "/users/webauthn/sessions", {phone: "4105550777"})
      end

      fill_in "Phone number", with: "4105550777"
      click_button "Continue with Phone"

      expect(page).to have_text(
        "Too many verification attempts. Please wait 5 minutes before trying again.", wait: 10
      )
      expect(page).to have_button("Continue with Phone", disabled: true)
    end
  end
end
