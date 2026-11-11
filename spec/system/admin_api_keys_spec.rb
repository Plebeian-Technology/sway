# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin API Keys", type: :system, js: true, phase16: true do
  let(:admin_phone) { "4105550002" }
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

  around do |example|
    original_admin_phones = User::ADMIN_PHONES.dup
    original_api_user_phones = User::API_USER_PHONES.dup

    begin
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, [admin_phone])
      User.send(:remove_const, :API_USER_PHONES)
      User.const_set(:API_USER_PHONES, [admin_phone])

      example.run
    ensure
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, original_admin_phones)
      User.send(:remove_const, :API_USER_PHONES)
      User.const_set(:API_USER_PHONES, original_api_user_phones)
    end
  end

  before do
    @signed_in_user = create(:user, phone: admin_phone)
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

  it "creates a new API key and displays the one-time token" do
    visit "/api_keys"
    wait_until_loaded

    expect(@signed_in_user.api_keys).to be_empty

    click_button "Create API Key"

    # The show-it-once token dialog appears, carried by the flash message
    expect(page).to have_text("New API Key", wait: 10)
    expect(page).to have_text("Store this new API Key securely")

    click_button "I saved my API Key"

    @signed_in_user.reload
    expect(@signed_in_user.api_keys).not_to be_empty
  end

  it "updates the name of an existing API key" do
    api_key = create(:api_key, bearer: @signed_in_user, name: nil)

    visit "/api_keys"
    wait_until_loaded

    # send_keys fires real keyboard events, which React's onChange listens for.
    # `set()` writes the value straight in, and React's controlled-input value
    # tracker does not notice, so the change is lost.
    name_input = first("table input")
    name_input.click
    name_input.send_keys("MyKey")

    # Wait for React to redraw the update button's onClick handler with the new
    # `newName` state. The button starts disabled, because newName is "", and
    # becomes enabled once React commits the state change from what we typed —
    # that same commit rebinds onClick to a handler holding newName="MyKey".
    expect(page).to have_css("#update-#{api_key.id}:not([disabled])")

    find("#update-#{api_key.id}").click

    # Wait for the Inertia post-then-redirect round trip — the table redraws with the new name as plain text
    expect(page).to have_css("table td", text: "MyKey", wait: 10)

    api_key.reload
    expect(api_key.name).to eq("MyKey")
  end

  it "deletes an existing API key" do
    api_key = create(:api_key, bearer: @signed_in_user, name: "ToDelete")

    visit "/api_keys"
    wait_until_loaded

    expect(page).to have_css("#delete-#{api_key.id}")

    delete_button = find("#delete-#{api_key.id}")
    page.execute_script("arguments[0].click()", delete_button)

    # Deleting an API key is destructive and irreversible, so it now asks first.
    expect(page).to have_text("Delete this API key?", wait: 5)
    find("[role='dialog']").click_button("Delete API Key")

    # After the Inertia post-then-redirect round trip the row, and its delete button, are gone
    expect(page).to have_no_css("#delete-#{api_key.id}", wait: 10)
    expect(ApiKey.where(id: api_key.id)).not_to exist
  end

  it "keeps the API key when the delete confirmation is cancelled" do
    api_key = create(:api_key, bearer: @signed_in_user, name: "KeepMe")

    visit "/api_keys"
    wait_until_loaded

    delete_button = find("#delete-#{api_key.id}")
    page.execute_script("arguments[0].click()", delete_button)

    expect(page).to have_text("Delete this API key?", wait: 5)
    find("[role='dialog']").click_button("Cancel")

    expect(page).to have_no_text("Delete this API key?", wait: 5)
    expect(page).to have_css("#delete-#{api_key.id}")
    expect(ApiKey.where(id: api_key.id)).to exist
  end
end
