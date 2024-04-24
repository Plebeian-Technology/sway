# typed: false
require "application_system_test_case"

class UserDistrictsTest < ApplicationSystemTestCase
  setup do
    @user_district = user_districts(:one)
  end

  test "visiting the index" do
    visit user_districts_url
    assert_selector "h1", text: "User districts"
  end

  test "should create user district" do
    visit user_districts_url
    click_on "New user district"

    fill_in "District", with: @user_district.district_id
    fill_in "User", with: @user_district.user_id
    click_on "Create User district"

    assert_text "User district was successfully created"
    click_on "Back"
  end

  test "should update User district" do
    visit user_district_url(@user_district)
    click_on "Edit this user district", match: :first

    fill_in "District", with: @user_district.district_id
    fill_in "User", with: @user_district.user_id
    click_on "Update User district"

    assert_text "User district was successfully updated"
    click_on "Back"
  end

  test "should destroy User district" do
    visit user_district_url(@user_district)
    click_on "Destroy this user district", match: :first

    assert_text "User district was successfully destroyed"
  end
end
