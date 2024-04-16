require "application_system_test_case"

class UserLegislatorScoresTest < ApplicationSystemTestCase
  setup do
    @user_legislator_score = user_legislator_scores(:one)
  end

  test "visiting the index" do
    visit user_legislator_scores_url
    assert_selector "h1", text: "User legislator scores"
  end

  test "should create user legislator score" do
    visit user_legislator_scores_url
    click_on "New user legislator score"

    fill_in "Count agreed", with: @user_legislator_score.count_agreed
    fill_in "Count disagreed", with: @user_legislator_score.count_disagreed
    fill_in "Count legislator abstained", with: @user_legislator_score.count_legislator_abstained
    fill_in "Count no legislator vote", with: @user_legislator_score.count_no_legislator_vote
    fill_in "User legislator", with: @user_legislator_score.user_legislator_id
    click_on "Create User legislator score"

    assert_text "User legislator score was successfully created"
    click_on "Back"
  end

  test "should update User legislator score" do
    visit user_legislator_score_url(@user_legislator_score)
    click_on "Edit this user legislator score", match: :first

    fill_in "Count agreed", with: @user_legislator_score.count_agreed
    fill_in "Count disagreed", with: @user_legislator_score.count_disagreed
    fill_in "Count legislator abstained", with: @user_legislator_score.count_legislator_abstained
    fill_in "Count no legislator vote", with: @user_legislator_score.count_no_legislator_vote
    fill_in "User legislator", with: @user_legislator_score.user_legislator_id
    click_on "Update User legislator score"

    assert_text "User legislator score was successfully updated"
    click_on "Back"
  end

  test "should destroy User legislator score" do
    visit user_legislator_score_url(@user_legislator_score)
    click_on "Destroy this user legislator score", match: :first

    assert_text "User legislator score was successfully destroyed"
  end
end
