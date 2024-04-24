# typed: false
require "application_system_test_case"

class UserVotesTest < ApplicationSystemTestCase
  setup do
    @user_vote = user_votes(:one)
  end

  test "visiting the index" do
    visit user_votes_url
    assert_selector "h1", text: "User votes"
  end

  test "should create user vote" do
    visit user_votes_url
    click_on "New user vote"

    fill_in "Bill", with: @user_vote.bill_id
    fill_in "Support", with: @user_vote.support
    fill_in "User", with: @user_vote.user_id
    click_on "Create User vote"

    assert_text "User vote was successfully created"
    click_on "Back"
  end

  test "should update User vote" do
    visit user_vote_url(@user_vote)
    click_on "Edit this user vote", match: :first

    fill_in "Bill", with: @user_vote.bill_id
    fill_in "Support", with: @user_vote.support
    fill_in "User", with: @user_vote.user_id
    click_on "Update User vote"

    assert_text "User vote was successfully updated"
    click_on "Back"
  end

  test "should destroy User vote" do
    visit user_vote_url(@user_vote)
    click_on "Destroy this user vote", match: :first

    assert_text "User vote was successfully destroyed"
  end
end
