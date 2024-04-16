require "application_system_test_case"

class SwayLocalesTest < ApplicationSystemTestCase
  setup do
    @sway_locale = sway_locales(:one)
  end

  test "visiting the index" do
    visit sway_locales_url
    assert_selector "h1", text: "Sway locales"
  end

  test "should create sway locale" do
    visit sway_locales_url
    click_on "New sway locale"

    fill_in "City", with: @sway_locale.city
    fill_in "Country", with: @sway_locale.country
    fill_in "State", with: @sway_locale.state
    click_on "Create Sway locale"

    assert_text "Sway locale was successfully created"
    click_on "Back"
  end

  test "should update Sway locale" do
    visit sway_locale_url(@sway_locale)
    click_on "Edit this sway locale", match: :first

    fill_in "City", with: @sway_locale.city
    fill_in "Country", with: @sway_locale.country
    fill_in "State", with: @sway_locale.state
    click_on "Update Sway locale"

    assert_text "Sway locale was successfully updated"
    click_on "Back"
  end

  test "should destroy Sway locale" do
    visit sway_locale_url(@sway_locale)
    click_on "Destroy this sway locale", match: :first

    assert_text "Sway locale was successfully destroyed"
  end
end
