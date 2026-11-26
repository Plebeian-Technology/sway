# frozen_string_literal: true

require "rails_helper"

# @lat: [[identity-and-access#The phone number is the account#First-passkey enrollment]]
RSpec.describe "Passkey management", type: :system, js: true do
  include_context "TwilioDouble"

  around do |example|
    initial_values = {} #: Hash[String, String?]
    env_overrides = {
      "TWILIO_ACCOUNT_SID" => "test-sid",
      "TWILIO_AUTH_TOKEN" => "test-token"
    }
    previous_values =
      env_overrides.each_with_object(initial_values) do |(key, _value), memo|
        memo[key] = ENV.fetch(key, nil)
      end

    begin
      env_overrides.each { |key, value| ENV[key] = value }

      # The add-a-passkey flow has to run the REAL phone check, and the skip
      # switch on would skip confirm_phone entirely. The server runs in a
      # thread of this same process, so the swapped setting is visible to it.
      with_app_config(:dev_login, skip_phone_verification: false) { example.run }
    ensure
      previous_values.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end
  end

  before do
    visit root_path
    @active_authenticators = [enable_virtual_authenticator]

    phone = "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}"
    @signed_in_user = register_passkey_user(phone: phone)
    complete_registration_with_active_link(@signed_in_user)
  end

  after do
    Array(@active_authenticators).reverse_each do |id|
      disable_virtual_authenticator(id)
    end
  end

  # The add-a-passkey request lists every credential the account already has and
  # tells the browser to refuse them, so adding another one from the SAME device
  # is rejected on purpose. Swap in a fresh fake authenticator to play the part
  # of a new device, the way webauthn_passkey_spec does.
  def swap_to_new_device
    disable_virtual_authenticator(@active_authenticators.pop)
    @active_authenticators << enable_virtual_authenticator
  end

  it "adds a passkey through the SMS-gated ceremony from a new device" do
    visit "/users/passkeys"
    wait_until_loaded

    expect(page).to have_text("Passkey Management", wait: 10)
    expect(page).to have_css("[data-testid='passkey-list']")

    # @lat: [[identity-and-access#The phone number is the account]]
    swap_to_new_device
    find("[data-testid='add-passkey-start']", wait: 10).click
    fill_in "add-passkey-code", with: "123456"
    fill_in "add-passkey-name", with: "My laptop"
    find("[data-testid='add-passkey-confirm']").click

    expect(page).to have_text("Passkey added.", wait: 15)
    expect(page).to have_text("My laptop")
    expect(Passkey.where(user_id: @signed_in_user.id).count).to eq(2)
    # Rejecting a reused device name, down to the exact server message, is
    # covered by spec/requests/users/passkeys_spec.rb.
  end

  # @lat: [[passkey-management-page-overview#Removing a passkey#The web remove flow]]
  it "removes one of two passkeys after an SMS check and a confirmation" do
    retired = create(:passkey, user: @signed_in_user, label: "Retired tablet")

    visit "/users/passkeys"
    wait_until_loaded

    within("[data-testid='passkey-row-#{retired.id}']", wait: 10) { click_button "Remove" }
    fill_in "remove-passkey-code", with: "123456", wait: 10
    find("[data-testid='remove-passkey-confirm-code']").click

    within("[role='dialog']", wait: 10) do
      expect(page).to have_text("Retired tablet")
      click_button "Remove"
    end

    expect(page).to have_text("Passkey removed.", wait: 15)
    expect(page).to have_no_css("[data-testid='passkey-row-#{retired.id}']", wait: 10)
    expect(Passkey.where(user_id: @signed_in_user.id).count).to eq(1)
    expect(Passkey.exists?(retired.id)).to be(false)
  end

  it "shows the empty state to a signed-in user with no passkeys" do
    passkey_free_user = create(:user)
    complete_registration_with_active_link(passkey_free_user)
    expect(Passkey.where(user_id: passkey_free_user.id).count).to eq(0)

    # sign_in_as only opens the session; admin status comes from the phone.
    sign_in_as(passkey_free_user)
    visit "/users/passkeys"
    wait_until_loaded

    expect(page).to have_text("Passkey Management", wait: 10)
    expect(page).to have_css("[data-testid='passkey-empty']", wait: 10)
    expect(page).to have_no_css("[data-testid='passkey-list']")
  end

  it "signs in with a discoverable passkey from the logged-out login panel" do
    # Throw away the session but leave the credential on the fake authenticator.
    page.driver.browser.manage.delete_all_cookies
    visit root_path
    expect(page).to have_button("Continue with Phone", wait: 10)

    click_button "Sign in with a passkey"

    # discoverable_callback works out who the user is from the signed response
    # alone, then sends a fully registered user to /feed.
    expect(page).to have_text("Feed", wait: 15)
    expect(page).to have_current_path("/feed", ignore_query: true)
  end
end
