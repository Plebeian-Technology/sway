require "application_system_test_case"

class UserLegislatorsTest < ApplicationSystemTestCase
  setup do
    @user_legislator = user_legislators(:one)
  end

  test "visiting the index" do
    visit user_legislators_url
    assert_selector "h1", text: "User legislators"
  end

  test "should create user legislator" do
    visit user_legislators_url
    click_on "New user legislator"

    fill_in "Legislator", with: @user_legislator.legislator_id
    fill_in "User", with: @user_legislator.user_id
    click_on "Create User legislator"

    assert_text "User legislator was successfully created"
    click_on "Back"
  end

  test "should update User legislator" do
    visit user_legislator_url(@user_legislator)
    click_on "Edit this user legislator", match: :first

    fill_in "Legislator", with: @user_legislator.legislator_id
    fill_in "User", with: @user_legislator.user_id
    click_on "Update User legislator"

    assert_text "User legislator was successfully updated"
    click_on "Back"
  end

  test "should destroy User legislator" do
    visit user_legislator_url(@user_legislator)
    click_on "Destroy this user legislator", match: :first

    assert_text "User legislator was successfully destroyed"
  end
end
