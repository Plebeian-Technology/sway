require "application_system_test_case"

class DistrictsTest < ApplicationSystemTestCase
  setup do
    @district = districts(:one)
  end

  test "visiting the index" do
    visit districts_url
    assert_selector "h1", text: "Districts"
  end

  test "should create district" do
    visit districts_url
    click_on "New district"

    fill_in "Name", with: @district.name
    click_on "Create District"

    assert_text "District was successfully created"
    click_on "Back"
  end

  test "should update District" do
    visit district_url(@district)
    click_on "Edit this district", match: :first

    fill_in "Name", with: @district.name
    click_on "Update District"

    assert_text "District was successfully updated"
    click_on "Back"
  end

  test "should destroy District" do
    visit district_url(@district)
    click_on "Destroy this district", match: :first

    assert_text "District was successfully destroyed"
  end
end
