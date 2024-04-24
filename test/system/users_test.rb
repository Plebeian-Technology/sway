# typed: false
require "application_system_test_case"

class UsersTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
  end

  test "visiting the index" do
    visit users_url
    assert_selector "h1", text: "Users"
  end

  test "should create user" do
    visit users_url
    click_on "New user"

    fill_in "Address", with: @user.address_id
    fill_in "Email", with: @user.email
    check "Is admin" if @user.is_admin
    check "Is email verified" if @user.is_email_verified
    check "Is registered to vote" if @user.is_registered_to_vote
    check "Is registration complete" if @user.is_registration_complete
    fill_in "Last login utc", with: @user.last_login_utc
    fill_in "Phone", with: @user.phone
    click_on "Create User"

    assert_text "User was successfully created"
    click_on "Back"
  end

  test "should update User" do
    visit user_url(@user)
    click_on "Edit this user", match: :first

    fill_in "Address", with: @user.address_id
    fill_in "Email", with: @user.email
    check "Is admin" if @user.is_admin
    check "Is email verified" if @user.is_email_verified
    check "Is registered to vote" if @user.is_registered_to_vote
    check "Is registration complete" if @user.is_registration_complete
    fill_in "Last login utc", with: @user.last_login_utc
    fill_in "Phone", with: @user.phone
    click_on "Update User"

    assert_text "User was successfully updated"
    click_on "Back"
  end

  test "should destroy User" do
    visit user_url(@user)
    click_on "Destroy this user", match: :first

    assert_text "User was successfully destroyed"
  end
end
